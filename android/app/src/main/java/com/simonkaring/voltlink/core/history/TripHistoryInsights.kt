package com.simonkaring.voltlink.core.history

import com.simonkaring.voltlink.data.TripRecord
import java.time.Instant
import java.time.ZoneId

/**
 * Aggregates completed trips into the period summary shown at the top of the trip log.
 *
 * Kept as a value type outside the view so the arithmetic (net energy, weighted efficiency,
 * cost) is testable without Compose or a live manager. Mirrors `TripHistoryInsights` on iOS.
 */
data class TripHistoryInsights(
    val tripCount: Int = 0,
    val distanceKm: Double = 0.0,
    /** Net energy drawn from the pack (used minus recovered), never negative. */
    val energyKWh: Double = 0.0,
    val efficiencyKWhPer100Km: Double = 0.0,
    val cost: Double = 0.0,
    val hasCost: Boolean = false,
) {
    companion object {
        val empty = TripHistoryInsights()

        /**
         * @param trips all recorded trips; incomplete (active) trips are ignored.
         * @param since inclusive start of the reporting period.
         * @param pricePerKWh user's electricity price; `0` disables the cost estimate.
         */
        fun summarize(
            trips: List<TripRecord>,
            since: Instant,
            pricePerKWh: Double = 0.0,
        ): TripHistoryInsights {
            val completed = trips.filter { trip ->
                trip.endTime != null && !trip.startTime.isBefore(since) &&
                    trip.distanceKm.isFinite() && trip.totalKWhUsed.isFinite()
            }
            if (completed.isEmpty()) return empty

            var distance = 0.0
            var energy = 0.0
            for (trip in completed) {
                distance += maxOf(0.0, trip.distanceKm)
                val recovered = trip.totalKWhRecovered
                val recoveredEnergy = if (recovered != null && recovered.isFinite()) {
                    maxOf(0.0, recovered)
                } else {
                    0.0
                }
                energy += maxOf(0.0, trip.totalKWhUsed - recoveredEnergy)
            }

            val efficiency = if (distance > 0.1) (energy / distance) * 100 else 0.0
            val price = if (pricePerKWh.isFinite() && pricePerKWh > 0) pricePerKWh else 0.0
            return TripHistoryInsights(
                tripCount = completed.size,
                distanceKm = distance,
                energyKWh = energy,
                efficiencyKWhPer100Km = efficiency,
                cost = energy * price,
                hasCost = price > 0,
            )
        }

        /** Start of the calendar month containing [date], used as the default period. */
        fun startOfMonth(date: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant =
            date.atZone(zone).toLocalDate().withDayOfMonth(1).atStartOfDay(zone).toInstant()
    }
}
