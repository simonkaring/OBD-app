package com.simonkaring.voltlink.core.telemetry

/**
 * Distance and energy integration for the trip recorder, kept pure so the arithmetic and its
 * freshness rules can be tested without a database, a clock or a coroutine scope.
 */
object TripMath {
    /** A longer gap means the recorder missed readings, so the energy total is incomplete. */
    const val MAX_INTERVAL_SECONDS = 300.0

    data class Progress(
        val distanceKm: Double,
        val kWhUsed: Double,
        val kWhRecovered: Double,
        val energyComplete: Boolean,
    )

    /**
     * Adds one interval of travel and energy. A value whose reading is stale is never
     * integrated: a frozen speed would otherwise keep counting kilometres while parked.
     */
    fun advance(
        distanceKm: Double,
        kWhUsed: Double,
        kWhRecovered: Double,
        energyComplete: Boolean,
        intervalSeconds: Double,
        speedKmH: Double,
        powerKW: Double,
        hasFreshSpeed: Boolean,
        hasFreshPower: Boolean,
        hasPowerData: Boolean,
        isCharging: Boolean,
    ): Progress {
        if (intervalSeconds <= 0.0) {
            return Progress(distanceKm, kWhUsed, kWhRecovered, energyComplete)
        }
        if (intervalSeconds >= MAX_INTERVAL_SECONDS) {
            return Progress(distanceKm, kWhUsed, kWhRecovered, false)
        }

        val hours = intervalSeconds / 3600.0
        val distance = if (hasFreshSpeed) distanceKm + speedKmH * hours else distanceKm
        var used = kWhUsed
        var recovered = kWhRecovered
        var complete = energyComplete
        if (!isCharging) {
            when {
                !hasPowerData || !hasFreshPower -> complete = false
                powerKW > 0 -> used += powerKW * hours
                // Regen only counts while the car is actually moving.
                powerKW < 0 && hasFreshSpeed && speedKmH >= 1 -> recovered -= powerKW * hours
            }
        }
        return Progress(distance, used, recovered, complete)
    }
}
