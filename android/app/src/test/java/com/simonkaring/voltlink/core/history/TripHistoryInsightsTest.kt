package com.simonkaring.voltlink.core.history

import com.simonkaring.voltlink.data.TripRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

class TripHistoryInsightsTest {
    private val since = Instant.ofEpochSecond(1_700_000_000)

    private fun trip(
        start: Instant,
        distanceKm: Double = 10.0,
        used: Double = 2.0,
        recovered: Double? = 0.2,
        completed: Boolean = true,
    ): TripRecord = TripRecord(
        startTime = start,
        endTime = if (completed) start.plusSeconds(600) else null,
        distanceKm = distanceKm,
        startSocPct = 80.0,
        totalKWhUsed = used,
        totalKWhRecovered = recovered,
    )

    @Test
    fun summarizeUsesNetEnergyAndWeightedEfficiency() {
        val trips = listOf(
            trip(since, distanceKm = 10.0, used = 2.0, recovered = 0.2),
            trip(since.plusSeconds(3_600), distanceKm = 30.0, used = 6.0, recovered = 0.5),
        )

        val insights = TripHistoryInsights.summarize(trips, since, pricePerKWh = 0.4)

        assertEquals(2, insights.tripCount)
        assertEquals(40.0, insights.distanceKm, 0.0001)
        assertEquals(7.3, insights.energyKWh, 0.0001)
        assertEquals(18.25, insights.efficiencyKWhPer100Km, 0.0001)
        assertTrue(insights.hasCost)
        assertEquals(2.92, insights.cost, 0.0001)
    }

    @Test
    fun ignoresTripsBeforeThePeriodAndActiveTrips() {
        val trips = listOf(
            trip(since.minusSeconds(1), distanceKm = 100.0, used = 20.0),
            trip(since.plusSeconds(60), distanceKm = 10.0, used = 2.0, completed = false),
            trip(since.plusSeconds(120), distanceKm = 5.0, used = 1.0),
        )

        val insights = TripHistoryInsights.summarize(trips, since, pricePerKWh = 0.0)

        assertEquals(1, insights.tripCount)
        assertEquals(5.0, insights.distanceKm, 0.0001)
        assertEquals(0.8, insights.energyKWh, 0.0001)
        assertFalse(insights.hasCost)
        assertEquals(0.0, insights.cost, 0.0001)
    }

    @Test
    fun zeroPriceHidesCostAndEmptyInputReturnsEmpty() {
        assertEquals(TripHistoryInsights.empty, TripHistoryInsights.summarize(emptyList(), Instant.now(), 0.3))

        val insights = TripHistoryInsights.summarize(listOf(trip(since)), since, pricePerKWh = 0.0)
        assertFalse(insights.hasCost)
        assertEquals(0.0, insights.cost, 0.0001)
        assertEquals(1, insights.tripCount)
    }

    @Test
    fun recoveredEnergyNeverMakesNetEnergyNegative() {
        val insights = TripHistoryInsights.summarize(
            listOf(trip(since, distanceKm = 10.0, used = 1.0, recovered = 5.0)),
            since,
            pricePerKWh = 0.5,
        )
        assertEquals(0.0, insights.energyKWh, 0.0001)
        assertEquals(0.0, insights.efficiencyKWhPer100Km, 0.0001)
    }

    @Test
    fun startOfMonthStripsDayAndTime() {
        // 1_700_000_000 is 2023-11-14T22:13:20Z.
        val start = TripHistoryInsights.startOfMonth(Instant.ofEpochSecond(1_700_000_000), ZoneId.of("UTC"))
        assertEquals(Instant.parse("2023-11-01T00:00:00Z"), start)
        assertEquals(java.time.LocalDate.of(2023, 11, 1), start.atZone(ZoneOffset.UTC).toLocalDate())
    }

    @Test
    fun summariesIgnoreATripWithoutPowerData() {
        // A trip whose energy columns never arrived must not skew the period totals.
        val insights = TripHistoryInsights.summarize(
            listOf(trip(since, distanceKm = Double.NaN)),
            since,
            pricePerKWh = 0.0,
        )
        assertEquals(TripHistoryInsights.empty, insights)
    }
}
