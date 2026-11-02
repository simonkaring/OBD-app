package com.simonkaring.voltlink.services

import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.HistoryStore
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * Records trips from the telemetry stream: integrates energy and distance, keeps one route
 * sample per second, and auto-starts/stops around a configurable stationary countdown.
 * Port of the iOS `TripTrackingManager` (distance comes from speed integration; there is no
 * background location service yet).
 */
class TripTracker(
    private val scope: CoroutineScope,
    private val store: HistoryStore,
) {
    data class State(
        val current: TripRecord? = null,
        val isRecording: Boolean = false,
        val averageConsumption: Double? = null,
        val stationarySecondsRemaining: Int? = null,
        val isAutoTripEnabled: Boolean = true,
        val error: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    var autoStopDelaySeconds: Int = 120
        set(value) {
            field = value.coerceAtLeast(30)
        }

    private var lastSampleTime: Instant? = null
    private var lastStoredSampleAt: Instant? = null
    private var lastSaveAt: Instant? = null
    private var samples = mutableListOf<TripSample>()
    private var stationaryJob: Job? = null
    private var stationarySince: Instant? = null
    private var hasCompleteEnergyData = true

    private val trips get() = store.trips

    val history: StateFlow<List<TripRecord>> get() = store.trips

    fun setAutoTrips(enabled: Boolean) {
        _state.value = _state.value.copy(isAutoTripEnabled = enabled)
        if (!enabled) resetStationary()
    }

    fun start(startSoc: Double, vehicleName: String) {
        if (_state.value.current != null) return
        val trip = TripRecord(
            startTime = Instant.now(),
            startSocPct = startSoc,
            endSocPct = startSoc,
            vehicleName = vehicleName,
        )
        samples = mutableListOf()
        lastSampleTime = null
        lastStoredSampleAt = null
        lastSaveAt = Instant.now()
        hasCompleteEnergyData = true
        resetStationary()
        _state.value = _state.value.copy(current = trip, isRecording = true, averageConsumption = null)
    }

    fun stop(endSoc: Double) {
        val trip = _state.value.current ?: return
        val finished = trip.copy(
            endTime = Instant.now(),
            endSocPct = endSoc,
            averageSpeedKmH = trip.computedAverageSpeedKmH,
        )
        scope.launch {
            try {
                store.saveTrip(finished, samples)
                _state.value = _state.value.copy(current = null, isRecording = false, averageConsumption = null)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "Trip history could not be saved: ${e.message}")
            }
        }
        resetStationary()
        lastSampleTime = null
        _state.value = _state.value.copy(isRecording = false)
    }

    fun deleteTrip(id: String) {
        scope.launch { store.deleteTrip(id) }
    }

    fun clearAll() {
        scope.launch { store.clearAllTrips() }
    }

    suspend fun loadSamples(tripId: String): List<TripSample> = store.loadTripSamples(tripId)

    /** Feeds a telemetry snapshot into the active trip and the auto start/stop policy. */
    fun process(snapshot: TelemetrySnapshot, vehicleName: String, hasPowerData: Boolean = true) {
        val state = _state.value
        if (state.isRecording) {
            record(snapshot, hasPowerData)
            if (state.isAutoTripEnabled) {
                if (snapshot.speedKmH < 1.0 || snapshot.isCharging) {
                    startStationaryCountdown(snapshot)
                } else {
                    resetStationary()
                }
            }
        } else if (state.isAutoTripEnabled) {
            resetStationary()
            if (snapshot.speedKmH >= 5.0) {
                start(snapshot.stateOfChargePct, vehicleName)
                record(snapshot, hasPowerData)
            }
        }
    }

    private fun startStationaryCountdown(snapshot: TelemetrySnapshot) {
        if (stationarySince == null) stationarySince = Instant.now()
        if (stationaryJob?.isActive == true) return
        stationaryJob = scope.launch {
            while (isActive) {
                val since = stationarySince ?: break
                val elapsed = Duration.between(since, Instant.now()).seconds
                val remaining = (autoStopDelaySeconds - elapsed).toInt().coerceAtLeast(0)
                _state.value = _state.value.copy(stationarySecondsRemaining = remaining)
                if (elapsed >= autoStopDelaySeconds) {
                    // Read SoC at fire time; the value captured at countdown start is stale.
                    stop(_state.value.current?.endSocPct ?: snapshot.stateOfChargePct)
                    break
                }
                delay(1_000)
            }
        }
    }

    private fun resetStationary() {
        stationaryJob?.cancel()
        stationaryJob = null
        stationarySince = null
        if (_state.value.stationarySecondsRemaining != null) {
            _state.value = _state.value.copy(stationarySecondsRemaining = null)
        }
    }

    private fun record(snapshot: TelemetrySnapshot, hasPowerData: Boolean) {
        val trip = _state.value.current ?: return
        val now = Instant.now()
        var distance = trip.distanceKm
        var used = trip.totalKWhUsed
        var recovered = trip.totalKWhRecovered

        lastSampleTime?.let { last ->
            val intervalSeconds = Duration.between(last, now).toMillis() / 1000.0
            if (intervalSeconds > 0 && intervalSeconds < 300) {
                if (!snapshot.isCharging) {
                    if (!hasPowerData) hasCompleteEnergyData = false
                    if (hasPowerData && snapshot.powerKW > 0) {
                        used += snapshot.powerKW * intervalSeconds / 3600.0
                    } else if (hasPowerData && snapshot.powerKW < 0 && snapshot.hasFreshSpeed && snapshot.speedKmH >= 1) {
                        recovered = (recovered ?: 0.0) - snapshot.powerKW * intervalSeconds / 3600.0
                    }
                }
                distance += snapshot.speedKmH * intervalSeconds / 3600.0
            } else if (intervalSeconds >= 300) {
                hasCompleteEnergyData = false
            }
        }
        lastSampleTime = now

        val updated = trip.copy(
            distanceKm = distance,
            totalKWhUsed = used,
            totalKWhRecovered = recovered,
            endSocPct = snapshot.stateOfChargePct,
            maxPowerKW = maxOf(trip.maxPowerKW, snapshot.powerKW),
            maxRegenKW = minOf(trip.maxRegenKW, snapshot.powerKW),
            averageSpeedKmH = trip.computedAverageSpeedKmH,
        )
        val consumption = if (hasCompleteEnergyData && hasPowerData && distance > 0.1) {
            updated.efficiencyKWhPer100Km
        } else {
            null
        }
        _state.value = _state.value.copy(current = updated, averageConsumption = consumption)

        lastSaveAt?.let { last ->
            if (Duration.between(last, now).seconds >= 30) {
                lastSaveAt = now
                val snapshotTrip = updated
                val sampleCopy = samples.toList()
                scope.launch { store.saveTrip(snapshotTrip, sampleCopy) }
            }
        }

        if (lastStoredSampleAt == null || Duration.between(lastStoredSampleAt, now).seconds >= 1) {
            lastStoredSampleAt = now
            // A recent fix gives the sample its route coordinate; without one it stays 0/0 and
            // the CSV column is blank, exactly like the iOS recorder before a fix arrives.
            val fix = TripLocation.fixFor(now)
            samples += TripSample(
                timestamp = now,
                latitude = fix?.latitude ?: 0.0,
                longitude = fix?.longitude ?: 0.0,
                speedKmH = snapshot.speedKmH,
                powerKW = snapshot.powerKW,
                socPct = snapshot.stateOfChargePct,
                batteryTempC = snapshot.batteryTempC,
            )
            if (samples.size > 14_400) samples = samples.takeLast(14_400).toMutableList()
        }
    }
}
