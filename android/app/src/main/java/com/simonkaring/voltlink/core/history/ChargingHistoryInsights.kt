package com.simonkaring.voltlink.core.history

import com.simonkaring.voltlink.data.ChargingSessionRecord
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

/**
 * Aggregates completed charging sessions into the period summary shown above the charging
 * history, mirroring the trip log's month card. Kept outside the view so energy, cost and the
 * AC/DC split are testable without Compose.
 */
data class ChargingHistoryInsights(
    val sessionCount: Int = 0,
    val energyKWh: Double = 0.0,
    val cost: Double = 0.0,
    val hasCost: Boolean = false,
    val dcSessions: Int = 0,
    val acSessions: Int = 0,
    /** Delivered energy over elapsed time across the period, not the mean of samples. */
    val averagePowerKW: Double = 0.0,
) {
    companion object {
        val empty = ChargingHistoryInsights()

        /**
         * @param sessions all recorded sessions; the in-flight one is ignored.
         * @param since inclusive start of the reporting period.
         * @param pricePerKWh user's electricity price; `0` disables the cost estimate.
         */
        fun summarize(
            sessions: List<ChargingSessionRecord>,
            since: Instant,
            pricePerKWh: Double = 0.0,
        ): ChargingHistoryInsights {
            val completed = sessions.filter { session ->
                session.endTime != null && !session.startTime.isBefore(since) &&
                    session.totalKWhDelivered.isFinite()
            }
            if (completed.isEmpty()) return empty

            var energy = 0.0
            var seconds = 0.0
            var dc = 0
            for (session in completed) {
                val end = session.endTime ?: continue
                energy += maxOf(0.0, session.totalKWhDelivered)
                seconds += Duration.between(session.startTime, end).seconds.coerceAtLeast(0)
                if (session.isDCCharging) dc++
            }

            val price = if (pricePerKWh.isFinite() && pricePerKWh > 0) pricePerKWh else 0.0
            return ChargingHistoryInsights(
                sessionCount = completed.size,
                energyKWh = energy,
                cost = energy * price,
                hasCost = price > 0,
                dcSessions = dc,
                acSessions = completed.size - dc,
                averagePowerKW = if (seconds > 0) energy / (seconds / 3600.0) else 0.0,
            )
        }

        /** Start of the calendar month containing [date], used as the default period. */
        fun startOfMonth(date: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant =
            TripHistoryInsights.startOfMonth(date, zone)
    }
}
