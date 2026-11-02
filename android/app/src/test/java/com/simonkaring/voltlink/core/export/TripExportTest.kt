package com.simonkaring.voltlink.core.export

import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TripExportTest {
    private val start = Instant.parse("2026-03-04T09:15:00Z")

    private fun sample(
        offsetSeconds: Long,
        latitude: Double = 48.1351,
        longitude: Double = 11.5820,
        speed: Double = 62.5,
        power: Double = 18.25,
        soc: Double = 71.5,
    ) = TripSample(
        timestamp = start.plusSeconds(offsetSeconds),
        latitude = latitude,
        longitude = longitude,
        speedKmH = speed,
        powerKW = power,
        socPct = soc,
        batteryTempC = 24.0,
    )

    private val trip = TripRecord(
        id = "trip-1",
        startTime = start,
        endTime = start.plusSeconds(600),
        distanceKm = 8.4,
        startSocPct = 74.0,
        endSocPct = 70.0,
        vehicleName = "Mercedes-Benz EQA 250",
    )

    @Test
    fun `csv keeps the iOS column order and formats numbers to three decimals`() {
        val rows = TripExport.csv(trip, listOf(sample(0))).trim().split("\n")
        assertEquals("timestamp,latitude,longitude,speed_kmh,power_kw,soc_pct,battery_temp_c", rows[0])
        assertEquals("2026-03-04T09:15:00Z,48.135100,11.582000,62.500,18.250,71.500,24.000", rows[1])
    }

    @Test
    fun `csv leaves coordinates blank without a position fix`() {
        val rows = TripExport.csv(trip, listOf(sample(0, latitude = 0.0, longitude = 0.0))).trim().split("\n")
        assertEquals("2026-03-04T09:15:00Z,,,62.500,18.250,71.500,24.000", rows[1])
    }

    @Test
    fun `csv sorts samples by time regardless of arrival order`() {
        val rows = TripExport.csv(trip, listOf(sample(2), sample(0))).trim().split("\n")
        assertTrue(rows[1].startsWith("2026-03-04T09:15:00Z"))
        assertTrue(rows[2].startsWith("2026-03-04T09:15:02Z"))
    }

    @Test
    fun `gpx writes only positioned samples and carries the telemetry extensions`() {
        val gpx = TripExport.gpx(trip, listOf(sample(0), sample(30, latitude = 0.0, longitude = 0.0)))
        assertTrue(gpx.startsWith("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        assertTrue(gpx.contains("<gpx version=\"1.1\" creator=\"VoltLink\""))
        assertEquals(1, Regex("<trkpt ").findAll(gpx).count())
        assertTrue(gpx.contains("<trkpt lat=\"48.135100\" lon=\"11.582000\">"))
        assertTrue(gpx.contains("<speed>62.500</speed>"))
        assertTrue(gpx.contains("<power>18.250</power>"))
        assertTrue(gpx.contains("<soc>71.500</soc>"))
    }

    @Test
    fun `gpx escapes markup in the track name`() {
        val named = trip.copy(vehicleName = "A&B <test>")
        val gpx = TripExport.gpx(named, listOf(sample(0)))
        assertTrue(gpx.contains("A&amp;B &lt;test&gt;"))
        assertFalse(gpx.contains("<test>"))
    }

    @Test
    fun `gpx route detection matches the share action visibility`() {
        assertFalse(TripExport.hasRoute(listOf(sample(0, latitude = 0.0, longitude = 0.0))))
        assertTrue(TripExport.hasRoute(listOf(sample(0))))
    }

    @Test
    fun `charging csv matches the iOS header and quotes fields containing commas`() {
        val session = ChargingSessionRecord(
            id = "session-1",
            startTime = start,
            endTime = start.plusSeconds(1_800),
            startSocPct = 32.0,
            endSocPct = 80.0,
            totalKWhDelivered = 33.125,
            peakPowerKW = 98.0,
            averagePowerKW = 66.25,
            locationName = "Ionity, Holzkirchen",
        )
        val rows = TripExport.chargingCsv(session).trim().split("\n")
        assertEquals(
            "start_time,end_time,duration_minutes,start_soc_pct,end_soc_pct,energy_kwh,peak_power_kw,average_power_kw,location,latitude,longitude",
            rows[0],
        )
        assertEquals(
            "2026-03-04T09:15:00Z,2026-03-04T09:45:00Z,30.0,32.000,80.000,33.125,98.000,66.250,\"Ionity, Holzkirchen\",,",
            rows[1],
        )
    }

    @Test
    fun `filenames follow the iOS naming scheme`() {
        assertTrue(
            TripExport.tripFilename(trip, "gpx").matches(Regex("VoltLink-Trip-\\d{4}-\\d{2}-\\d{2}\\.gpx")),
        )
        val session = ChargingSessionRecord(id = "s", startTime = start)
        assertTrue(
            TripExport.chargingFilename(session, "csv").matches(Regex("VoltLink-Charging-\\d{4}-\\d{2}-\\d{2}\\.csv")),
        )
    }
}
