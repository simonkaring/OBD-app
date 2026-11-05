package com.simonkaring.voltlink.core.backup

import com.simonkaring.voltlink.data.BatteryHealthRecord
import com.simonkaring.voltlink.data.ChargingSample
import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class HistoryBackupTest {
    private val start = Instant.parse("2026-10-24T07:30:00Z")

    @Test
    fun `battery health day key follows the local day`() {
        val morning = BackupBatteryHealth(start.toEpochMilli(), 95.0, "EQA")
        val later = BackupBatteryHealth(start.toEpochMilli() + 3_600_000, 95.4, "EQA")
        val nextDay = BackupBatteryHealth(start.toEpochMilli() + 30 * 3_600_000, 95.4, "EQA")
        assertEquals(morning.dayKey, later.dayKey)
        assertNotEquals(morning.dayKey, nextDay.dayKey)
    }

    private fun trip(id: String = "t1") = TripRecord(
        id = id,
        startTime = start,
        endTime = start.plusSeconds(3_600),
        distanceKm = 42.5,
        startSocPct = 78.0,
        endSocPct = 64.0,
        totalKWhUsed = 7.1,
        totalKWhRecovered = 1.3,
        averageSpeedKmH = 42.5,
        maxPowerKW = 120.0,
        maxRegenKW = -35.0,
        vehicleName = "Mercedes-Benz EQA 250",
        samples = listOf(
            TripSample(start, latitude = 52.52, longitude = 13.405, speedKmH = 50.0, powerKW = 20.0, socPct = 78.0),
            TripSample(start.plusSeconds(1), latitude = 52.53, longitude = 13.41, speedKmH = 55.0, powerKW = 22.0, socPct = 77.9),
        ),
    )

    private fun session(id: String = "c1") = ChargingSessionRecord(
        id = id,
        startTime = start,
        endTime = start.plusSeconds(1_800),
        startSocPct = 42.0,
        endSocPct = 80.0,
        totalKWhDelivered = 24.0,
        peakPowerKW = 120.0,
        averagePowerKW = 80.0,
        locationName = "Ionity",
        latitude = 52.52,
        longitude = 13.405,
        startBatteryTempC = 31.0,
        endBatteryTempC = 38.5,
        startRangeKm = 280.0,
        endRangeKm = 360.0,
        isDC = true,
        samples = listOf(ChargingSample(start, 42.0, 118.0), ChargingSample(start.plusSeconds(60), 45.0, 110.0)),
    )

    private fun health(time: Instant = start, vehicle: String = "Mercedes-Benz EQA 250") =
        BatteryHealthRecord(time, 97.4, vehicle)

    @Test
    fun roundTripsThroughJsonWithoutLosingSamples() {
        val backup = HistoryBackup.capture(listOf(trip()), listOf(session()), listOf(health()))

        val restored = HistoryBackup.fromJson(backup.toJson())

        assertEquals(HistoryBackup.CURRENT_VERSION, restored.version)
        val restoredTrip = restored.trips.single()
        assertEquals("t1", restoredTrip.id)
        assertEquals(42.5, restoredTrip.distanceKm, 1e-9)
        assertEquals(-35.0, restoredTrip.maxRegenKW, 1e-9)
        assertEquals(2, restoredTrip.samples.size)
        assertEquals(52.52, restoredTrip.samples.first().latitude, 1e-9)

        val restoredSession = restored.chargingSessions.single()
        assertEquals("Ionity", restoredSession.locationName)
        assertEquals(52.52, restoredSession.latitude!!, 1e-9)
        assertEquals(31.0, restoredSession.startBatteryTempC!!, 1e-9)
        assertEquals(360.0, restoredSession.endRangeKm!!, 1e-9)
        assertEquals(true, restoredSession.isDC)
        assertEquals(2, restoredSession.samples.size)

        assertEquals(97.4, restored.batteryHealth.single().sohPct, 1e-9)

        // The converted domain rows match their originals.
        val record = restoredTrip.toRecord()
        assertEquals(start, record.startTime)
        assertEquals(start.plusSeconds(3_600), record.endTime)
        assertEquals(2, restoredTrip.toSamples().size)
        assertEquals(118.0, restoredSession.toRecord().samples.first().powerKW, 1e-9)
    }

    @Test
    fun emptyHistoryProducesAnEmptyDocumentThatStillParses() {
        val backup = HistoryBackup.capture(emptyList(), emptyList(), emptyList())
        assertTrue(backup.isEmpty)
        assertTrue(HistoryBackup.fromJson(backup.toJson()).isEmpty)
    }

    @Test
    fun rejectsUnknownFutureVersions() {
        val json = HistoryBackup(trips = listOf(BackupTrip("t1", start.toEpochMilli())), version = 99).toJson()
        val error = runCatching { HistoryBackup.fromJson(json) }.exceptionOrNull()
        assertTrue(error is IllegalArgumentException)
        assertTrue(error!!.message!!.contains("unsupported backup version 99"))
    }

    @Test
    fun mergePlanSkipsRowsThatAlreadyExist() {
        val backup = HistoryBackup.capture(
            listOf(trip("t1"), trip("t2")),
            listOf(session("c1"), session("c2")),
            listOf(health(), health(start.plusSeconds(86_400)), health(start, "Other Car")),
        )

        val plan = BackupPlan.of(
            backup = backup,
            existingTripIds = setOf("t1"),
            existingSessionIds = setOf("c2"),
            existingHealthDayKeys = setOf(BackupBatteryHealth(start.toEpochMilli(), 97.4, "Mercedes-Benz EQA 250").dayKey),
        )

        assertEquals(listOf("t2"), plan.trips.map { it.id })
        assertEquals(listOf("c1"), plan.chargingSessions.map { it.id })
        // Same day + vehicle is deduped; the next day and the other vehicle are kept.
        assertEquals(2, plan.batteryHealth.size)
        assertFalse(plan.isEmpty)
        assertEquals("Restored 1 trips, 1 charges, 2 battery readings", plan.summary)
    }

    @Test
    fun mergePlanIsEmptyWhenNothingIsMissing() {
        val backup = HistoryBackup.capture(listOf(trip("t1")), listOf(session("c1")), listOf(health()))
        val plan = BackupPlan.of(
            backup,
            existingTripIds = setOf("t1"),
            existingSessionIds = setOf("c1"),
            existingHealthDayKeys = setOf(BackupBatteryHealth(start.toEpochMilli(), 97.4, "Mercedes-Benz EQA 250").dayKey),
        )
        assertTrue(plan.isEmpty)
    }
}
