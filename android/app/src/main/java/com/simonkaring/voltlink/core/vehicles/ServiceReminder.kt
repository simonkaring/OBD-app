package com.simonkaring.voltlink.core.vehicles

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The most recent service distance a vehicle profile has reported. */
data class ServiceIntervalSnapshot(
    val remainingKm: Double,
    val observedAtMillis: Long,
)

/** Key-value slice of the reminder state; `SharedPreferences` in the app, a map in tests. */
interface ServiceReminderStore {
    fun getDouble(key: String): Double?
    fun putDouble(key: String, value: Double)
    fun getLong(key: String): Long?
    fun putLong(key: String, value: Long)
}

/**
 * Remembers the vehicle-reported distance to the next service and raises a local alert when it
 * gets close. Port of the iOS `ServiceReminderMonitor`: the EQA (OBDb) profile decodes the
 * metric but nothing else surfaces it, so the last reading per vehicle is kept and turned into
 * a weekly reminder instead of a number buried in a metric tile.
 */
class ServiceReminderMonitor(private val store: ServiceReminderStore) {

    object Key {
        const val THRESHOLD_KM = "service.reminderThresholdKm"
        const val LAST_DISTANCE_PREFIX = "service.lastDistance."
        const val LAST_OBSERVED_PREFIX = "service.lastObserved."
        const val LAST_NOTIFIED_PREFIX = "service.lastNotified."
    }

    companion object {
        const val DEFAULT_THRESHOLD_KM = 1_000.0

        /** One reminder a week is enough; the flag is per vehicle so two cars do not share it. */
        const val REMINDER_COOLDOWN_MS = 7L * 86_400_000L

        /** Thresholds offered in Settings, in kilometers. */
        val options = listOf(500.0, 1_000.0, 2_000.0, 5_000.0)

        /** Matches `TelemetryMetric.SERVICE_DISTANCE`'s plausibility bound. */
        val plausibleRange = 0.0..65_535.0

        /** Pure decision used by [observe] and tested without any storage. */
        fun shouldRemind(
            remainingKm: Double,
            thresholdKm: Double,
            lastNotifiedAtMillis: Long?,
            enabled: Boolean,
            atMillis: Long,
        ): Boolean {
            if (!enabled || !remainingKm.isFinite() || !thresholdKm.isFinite() || thresholdKm <= 0) return false
            if (remainingKm > thresholdKm) return false
            if (lastNotifiedAtMillis == null) return true
            return atMillis - lastNotifiedAtMillis >= REMINDER_COOLDOWN_MS
        }
    }

    private val _thresholdKm = MutableStateFlow(loadThreshold())
    val thresholdKm: StateFlow<Double> = _thresholdKm.asStateFlow()

    /** Latest stored reading for the vehicle currently in use; null until one is decoded. */
    private val _latest = MutableStateFlow<ServiceIntervalSnapshot?>(null)
    val latest: StateFlow<ServiceIntervalSnapshot?> = _latest.asStateFlow()

    fun setThresholdKm(value: Double) {
        if (value !in options) return
        store.putDouble(Key.THRESHOLD_KM, value)
        _thresholdKm.value = value
    }

    fun snapshot(vehicleName: String): ServiceIntervalSnapshot? {
        if (vehicleName.isEmpty()) return null
        val distance = store.getDouble(Key.LAST_DISTANCE_PREFIX + vehicleName) ?: return null
        val observedAt = store.getLong(Key.LAST_OBSERVED_PREFIX + vehicleName) ?: return null
        return ServiceIntervalSnapshot(distance, observedAt)
    }

    /** Loads the stored reading for a vehicle, e.g. after switching profiles. */
    fun refresh(vehicleName: String) {
        _latest.value = snapshot(vehicleName)
    }

    /**
     * Stores the latest reading and reports whether the driver should be reminded now.
     *
     * - Returns: the stored snapshot, plus whether a reminder is due. A reading outside the
     *   plausible range is ignored entirely.
     */
    fun observe(
        distanceKm: Double,
        vehicleName: String,
        enabled: Boolean,
        atMillis: Long = System.currentTimeMillis(),
    ): ServiceReminderOutcome? {
        if (!distanceKm.isFinite() || distanceKm !in plausibleRange || vehicleName.isEmpty()) return null

        // Telemetry arrives about once a second; only touch storage when the value changed or
        // the timestamp is old enough to be worth refreshing.
        val previous = snapshot(vehicleName)
        val valueChanged = previous?.remainingKm != distanceKm
        val stale = previous == null || atMillis - previous.observedAtMillis >= 60_000L
        if (valueChanged || stale) {
            store.putDouble(Key.LAST_DISTANCE_PREFIX + vehicleName, distanceKm)
            store.putLong(Key.LAST_OBSERVED_PREFIX + vehicleName, atMillis)
        }

        val lastNotified = store.getLong(Key.LAST_NOTIFIED_PREFIX + vehicleName)
        val remind = shouldRemind(distanceKm, _thresholdKm.value, lastNotified, enabled, atMillis)
        if (remind) {
            store.putLong(Key.LAST_NOTIFIED_PREFIX + vehicleName, atMillis)
        }
        val snapshot = ServiceIntervalSnapshot(distanceKm, atMillis)
        _latest.value = snapshot
        return ServiceReminderOutcome(snapshot, remind)
    }

    private fun loadThreshold(): Double {
        val stored = store.getDouble(Key.THRESHOLD_KM)
        return if (stored != null && stored in options) stored else DEFAULT_THRESHOLD_KM
    }
}

data class ServiceReminderOutcome(
    val snapshot: ServiceIntervalSnapshot,
    val reminderDue: Boolean,
)
