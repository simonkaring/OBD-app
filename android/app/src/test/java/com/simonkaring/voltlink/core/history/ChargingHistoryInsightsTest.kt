package com.simonkaring.voltlink.core.history

import com.simonkaring.voltlink.data.ChargingSessionRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ChargingHistoryInsightsTest {
    private val monthStart = Instant.parse("2026-11-01T00:00:00Z")

    private fun session(
        id: String = "c1",
        start: Instant = monthStart.plusSeconds(3_600),
        minutes: Long = 30,
        energy: Double = 20.0,
        peak: Double = 80.0,
        isDC: Boolean? = null,
    ) = ChargingSessionRecord(
        id = id,
        startTime = start,
        endTime = start.plusSeconds(minutes * 60),
        totalKWhDelivered = energy,
        peakPowerKW = peak,
        isDC = isDC,
    )

    @Test
    fun `sums energy, cost and the ac dc split`() {
        val insights = ChargingHistoryInsights.summarize(
            sessions = listOf(
                session("dc", energy = 30.0, minutes = 30, peak = 120.0, isDC = true),
                session("ac", start = monthStart.plusSeconds(7_200), energy = 10.0, minutes = 120, peak = 11.0, isDC = false),
            ),
            since = monthStart,
            pricePerKWh = 0.4,
        )

        assertEquals(2, insights.sessionCount)
        assertEquals(40.0, insights.energyKWh, 1e-9)
        assertEquals(16.0, insights.cost, 1e-9)
        assertTrue(insights.hasCost)
        assertEquals(1, insights.dcSessions)
        assertEquals(1, insights.acSessions)
        // 40 kWh over 2.5 h, not the mean of the two sessions' peak rates.
        assertEquals(16.0, insights.averagePowerKW, 1e-9)
    }

    @Test
    fun `rows without a recorded class fall back to peak power`() {
        val insights = ChargingHistoryInsights.summarize(
            sessions = listOf(
                session("old-dc", peak = 90.0, isDC = null),
                session("old-ac", start = monthStart.plusSeconds(7_200), peak = 11.0, isDC = null),
            ),
            since = monthStart,
        )

        assertEquals(1, insights.dcSessions)
        assertEquals(1, insights.acSessions)
        assertFalse(insights.hasCost)
    }

    @Test
    fun `sessions outside the period and still charging are ignored`() {
        val insights = ChargingHistoryInsights.summarize(
            sessions = listOf(
                session("before", start = monthStart.minusSeconds(86_400)),
                session("open").copy(endTime = null),
                session("kept"),
            ),
            since = monthStart,
        )

        assertEquals(1, insights.sessionCount)
        assertEquals(20.0, insights.energyKWh, 1e-9)
    }

    @Test
    fun `empty input and a zero price keep the summary empty and free of cost`() {
        assertTrue(ChargingHistoryInsights.summarize(emptyList(), monthStart).sessionCount == 0)
        val insights = ChargingHistoryInsights.summarize(listOf(session()), monthStart, pricePerKWh = 0.0)
        assertEquals(0.0, insights.cost, 0.0)
        assertFalse(insights.hasCost)
    }
}
