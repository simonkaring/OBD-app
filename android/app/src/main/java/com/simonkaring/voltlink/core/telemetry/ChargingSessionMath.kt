package com.simonkaring.voltlink.core.telemetry

import java.time.Duration
import java.time.Instant

/** Session arithmetic shared by the live charging card and the stored record. */
object ChargingSessionMath {
    /**
     * Delivered energy over elapsed time — the figure a charger reports too. `null` until
     * enough time has passed to divide by, so callers keep the last known value.
     */
    fun averagePowerKW(energyKWh: Double, start: Instant, end: Instant): Double? {
        val hours = Duration.between(start, end).toMillis() / 3_600_000.0
        return if (hours > 0.01 && energyKWh.isFinite()) energyKWh / hours else null
    }
}
