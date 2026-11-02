package com.simonkaring.voltlink.core.telemetry

import java.time.Instant

/**
 * Estimates charging power from the SoC slope when a profile cannot report pack current or
 * an explicit charge rate. The 90 s window and 30 s minimum span mirror the iOS estimator.
 */
class ChargingPowerEstimator {
    private data class Sample(val timestamp: Instant, val soc: Double)

    private val history = ArrayDeque<Sample>()

    fun reset() = history.clear()

    /** Clears an estimate that outlived its SoC reading or must yield to a measured value. */
    fun clear(snapshot: TelemetrySnapshot): TelemetrySnapshot {
        if (snapshot.chargePowerSource != ChargePowerSource.SOC_ESTIMATE) return snapshot
        return snapshot.copy(
            isCharging = false,
            chargePowerKW = 0.0,
            chargePowerUpdatedAt = null,
            chargePowerSource = null,
        )
    }

    /** Drops the history window and the published estimate; true when the snapshot changed. */
    fun invalidate(snapshot: TelemetrySnapshot): Pair<TelemetrySnapshot, Boolean> {
        if (snapshot.chargePowerSource != ChargePowerSource.SOC_ESTIMATE) return snapshot to false
        reset()
        return clear(snapshot) to true
    }

    fun update(
        soc: Double,
        capacityKWh: Double,
        timestamp: Instant,
        chargingPermitted: Boolean,
        snapshot: TelemetrySnapshot,
    ): TelemetrySnapshot {
        // A profile that reports pack current has better information than an SoC slope.
        val measuredAt = snapshot.chargePowerUpdatedAt
        if (snapshot.chargePowerSource == ChargePowerSource.MEASURED && measuredAt != null) {
            val ageMs = timestamp.toEpochMilli() - measuredAt.toEpochMilli()
            if (ageMs < 10_000) return snapshot
        }

        if (!capacityKWh.isFinite() || capacityKWh <= 0.0 || !chargingPermitted) {
            reset()
            return clear(snapshot)
        }

        history.addLast(Sample(timestamp, soc))
        val cutoff = timestamp.toEpochMilli() - 90_000
        while (history.isNotEmpty() && history.first().timestamp.toEpochMilli() < cutoff) {
            history.removeFirst()
        }

        val oldest = history.firstOrNull() ?: return snapshot
        val durationSeconds = (timestamp.toEpochMilli() - oldest.timestamp.toEpochMilli()) / 1000.0
        val delta = soc - oldest.soc
        if (durationSeconds < 30.0) return snapshot
        if (delta <= 0.0) return clear(snapshot)

        val kw = (delta / 100.0 * capacityKWh) / (durationSeconds / 3600.0)
        if (kw !in 0.5..200.0) return clear(snapshot)

        return snapshot.copy(
            isCharging = true,
            chargePowerKW = kw,
            chargePowerUpdatedAt = timestamp,
            chargePowerSource = ChargePowerSource.SOC_ESTIMATE,
        )
    }
}
