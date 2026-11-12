package com.simonkaring.voltlink.services

import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.TripHistoryStore
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class TripTrackerTest {

    private class FakeTripHistoryStore : TripHistoryStore {
        private val _trips = MutableStateFlow<List<TripRecord>>(emptyList())
        override val trips: StateFlow<List<TripRecord>> = _trips.asStateFlow()

        val savedTrips = mutableListOf<Pair<TripRecord, List<TripSample>>>()

        override suspend fun saveTrip(trip: TripRecord, samples: List<TripSample>) {
            savedTrips += trip to samples
            _trips.value = _trips.value + trip
        }

        override suspend fun saveTripProgress(trip: TripRecord, newSamples: List<TripSample>) {
            val existing = savedTrips.indexOfFirst { it.first.id == trip.id }
            if (existing >= 0) {
                val current = savedTrips[existing]
                savedTrips[existing] = trip to (current.second + newSamples)
            } else {
                savedTrips += trip to newSamples
            }
        }

        override suspend fun deleteTrip(id: String) {
            savedTrips.removeAll { it.first.id == id }
            _trips.value = _trips.value.filterNot { it.id == id }
        }

        override suspend fun clearAllTrips() {
            savedTrips.clear()
            _trips.value = emptyList()
        }

        override suspend fun loadTripSamples(tripId: String): List<TripSample> =
            savedTrips.firstOrNull { it.first.id == tripId }?.second ?: emptyList()
    }

    private val testScope = TestScope()
    private val fakeStore = FakeTripHistoryStore()
    private val tracker = TripTracker(testScope, fakeStore)

    @Test
    fun manualTripStartAndStopCalculatesAverageSpeed() = testScope.runTest {
        tracker.start(startSoc = 90.0, vehicleName = "EQA 250")
        assertTrue(tracker.state.value.isRecording)
        assertEquals(90.0, tracker.state.value.current!!.startSocPct, 0.01)

        val now = Instant.now()
        val snap1 = TelemetrySnapshot(
            speedKmH = 60.0,
            speedUpdatedAt = now,
            powerKW = 20.0,
            powerUpdatedAt = now,
            stateOfChargePct = 89.0,
        )
        tracker.process(snap1, vehicleName = "EQA 250")

        Thread.sleep(50) // advance time slightly

        val now2 = Instant.now()
        val snap2 = TelemetrySnapshot(
            speedKmH = 80.0,
            speedUpdatedAt = now2,
            powerKW = 25.0,
            powerUpdatedAt = now2,
            stateOfChargePct = 88.0,
        )
        tracker.process(snap2, vehicleName = "EQA 250")

        tracker.stop(endSoc = 88.0)
        testScheduler.advanceUntilIdle()

        assertFalse(tracker.state.value.isRecording)
        assertNull(tracker.state.value.current)
        assertEquals(1, fakeStore.savedTrips.size)

        val (savedTrip, savedSamples) = fakeStore.savedTrips.first()
        assertEquals(88.0, savedTrip.endSocPct, 0.01)
        assertNotNull(savedTrip.endTime)
        // Average speed must not be 0.0 when samples with speed were recorded
        assertTrue("Average speed should be greater than 0, was ${savedTrip.averageSpeedKmH}", savedTrip.averageSpeedKmH > 0.0)
    }

    @Test
    fun autoStartsWhenSpeedExceedsFiveKmH() = testScope.runTest {
        tracker.setAutoTrips(true)

        val now = Instant.now()
        val slowSnap = TelemetrySnapshot(speedKmH = 2.0, speedUpdatedAt = now, stateOfChargePct = 85.0)
        tracker.process(slowSnap, vehicleName = "EQA 250")
        assertFalse(tracker.state.value.isRecording)

        val fastSnap = TelemetrySnapshot(speedKmH = 15.0, speedUpdatedAt = now, stateOfChargePct = 85.0)
        tracker.process(fastSnap, vehicleName = "EQA 250")
        assertTrue(tracker.state.value.isRecording)
        assertNotNull(tracker.state.value.current)
    }

    @Test
    fun demoModeDoesNotPersistToStore() = testScope.runTest {
        tracker.setDemoMode(true)
        tracker.start(startSoc = 80.0, vehicleName = "Demo EQA")
        assertTrue(tracker.state.value.isRecording)

        val now = Instant.now()
        val snap = TelemetrySnapshot(speedKmH = 50.0, speedUpdatedAt = now, stateOfChargePct = 79.0)
        tracker.process(snap, vehicleName = "Demo EQA")

        tracker.stop(endSoc = 79.0)
        testScheduler.advanceUntilIdle()

        assertFalse(tracker.state.value.isRecording)
        assertTrue(fakeStore.savedTrips.isEmpty())
    }
}
