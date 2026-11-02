package com.simonkaring.voltlink.services

import com.simonkaring.voltlink.core.telemetry.ChargingCurveSample
import com.simonkaring.voltlink.core.telemetry.ChargingTimeEstimator
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.ChargingSample
import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.HistoryStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * Records charging sessions from the telemetry stream and projects time-to-target by
 * integrating the session's own power curve. Port of the iOS `ChargingTrackingManager` +
 * `ChargingSessionTracker`.
 */
class ChargingTracker(
    private val scope: CoroutineScope,
    private val store: HistoryStore,
) {
    data class State(
        val current: ChargingSessionRecord? = null,
        val isCharging: Boolean = false,
        val secondsToTarget: Double? = null,
        val targetPercent: Double = 80.0,
        val lastCompletedTargetReached: Boolean = false,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    val history: StateFlow<List<ChargingSessionRecord>> get() = store.chargingSessions

    /**
     * A simulated session drives the live card but never reaches the history database.
     * Switching sources closes an in-flight session under the mode it was started in.
     */
    var isDemoMode: Boolean = false
        private set

    fun setDemoMode(enabled: Boolean) {
        if (enabled == isDemoMode) return
        _state.value.current?.let { session ->
            if (enabled) closeSession(session, Instant.now()) else discardSession()
        }
        isDemoMode = enabled
    }

    private var capacityKWh = 66.5
    private var lastUpdate: Instant? = null
    private var lastSampleAt: Instant? = null
    private var lastChargingAt: Instant? = null
    private var chargedKWh = 0.0
    private var powerAccumulator = 0.0
    private var powerSamples = 0
    private var targetReachedNotified = false

    fun updateCapacity(kWh: Double) {
        if (kWh > 0) capacityKWh = kWh
    }

    /** Feeds a telemetry snapshot; starts, updates and closes sessions as charging changes. */
    fun onTelemetry(snapshot: TelemetrySnapshot, targetPercent: Double) {
        val now = snapshot.timestamp
        val charging = snapshot.isCharging && snapshot.speedKmH < 1.0
        val session = _state.value.current

        if (charging) {
            lastChargingAt = now
            if (session == null) {
                startSession(snapshot, now)
            } else {
                updateSession(session, snapshot, now)
            }
            val seconds = ChargingTimeEstimator.secondsToTarget(
                currentSoc = snapshot.stateOfChargePct,
                targetSoc = targetPercent,
                currentPowerKW = snapshot.chargePowerKW,
                capacityKWh = capacityKWh,
                observedCurve = _state.value.current?.samples.orEmpty().map { ChargingCurveSample(it.socPct, it.powerKW) },
            )
            val reached = snapshot.stateOfChargePct >= targetPercent - 0.01
            _state.value = _state.value.copy(
                isCharging = true,
                secondsToTarget = seconds,
                targetPercent = targetPercent,
                lastCompletedTargetReached = if (reached && !targetReachedNotified) {
                    targetReachedNotified = true
                    true
                } else {
                    _state.value.lastCompletedTargetReached
                },
            )
        } else {
            val last = lastChargingAt
            val ended = last != null && Duration.between(last, now).seconds >= 90
            if (session != null && ended) {
                closeSession(session, now)
            }
            if (_state.value.isCharging) {
                _state.value = _state.value.copy(isCharging = false, secondsToTarget = null)
            }
        }
        lastUpdate = now
    }

    fun deleteSession(id: String) {
        scope.launch { store.deleteChargingSession(id) }
    }

    private fun startSession(snapshot: TelemetrySnapshot, now: Instant) {
        chargedKWh = 0.0
        powerAccumulator = 0.0
        powerSamples = 0
        targetReachedNotified = false
        lastSampleAt = null
        val session = ChargingSessionRecord(
            startTime = now,
            startSocPct = snapshot.stateOfChargePct,
            endSocPct = snapshot.stateOfChargePct,
            locationName = if (snapshot.chargePowerKW > 22.0) "DC Fast Charger" else "AC Charger",
        )
        _state.value = _state.value.copy(current = session, isCharging = true)
        updateSession(session, snapshot, now)
    }

    private fun updateSession(session: ChargingSessionRecord, snapshot: TelemetrySnapshot, now: Instant) {
        val power = snapshot.chargePowerKW.coerceAtLeast(0.0)
        lastUpdate?.let { last ->
            val seconds = Duration.between(last, now).toMillis() / 1000.0
            if (seconds in 0.0..300.0) chargedKWh += power * seconds / 3600.0
        }
        lastUpdate = now
        if (power > 0) {
            powerAccumulator += power
            powerSamples += 1
        }

        val newSamples = session.samples.toMutableList()
        val shouldSample = lastSampleAt == null ||
            Duration.between(lastSampleAt, now).seconds >= 30 ||
            (newSamples.lastOrNull()?.let { kotlin.math.abs(it.socPct - snapshot.stateOfChargePct) >= 1.0 } ?: true)
        if (shouldSample) {
            lastSampleAt = now
            newSamples += ChargingSample(now, snapshot.stateOfChargePct, power)
        }

        val updated = session.copy(
            endSocPct = snapshot.stateOfChargePct,
            totalKWhDelivered = chargedKWh,
            peakPowerKW = maxOf(session.peakPowerKW, power),
            averagePowerKW = if (powerSamples > 0) powerAccumulator / powerSamples else session.averagePowerKW,
            samples = newSamples,
        )
        _state.value = _state.value.copy(current = updated)
    }

    private fun closeSession(session: ChargingSessionRecord, now: Instant) {
        val finished = session.copy(
            endTime = lastChargingAt ?: now,
            averagePowerKW = if (powerSamples > 0) powerAccumulator / powerSamples else session.averagePowerKW,
        )
        if (!isDemoMode) scope.launch { store.saveChargingSession(finished) }
        discardSession()
    }

    private fun discardSession() {
        _state.value = _state.value.copy(current = null, isCharging = false, secondsToTarget = null)
        lastUpdate = null
        lastChargingAt = null
    }
}
