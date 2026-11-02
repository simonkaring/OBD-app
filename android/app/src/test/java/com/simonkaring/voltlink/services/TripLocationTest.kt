package com.simonkaring.voltlink.services

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TripLocationTest {
    private val now = Instant.parse("2026-10-25T09:00:00Z")

    private fun fix(
        at: Instant = now,
        latitude: Double = 52.5200,
        longitude: Double = 13.4050,
        accuracy: Float = 8f,
    ) = LocationFix(at, latitude, longitude, altitudeM = 34.0, speedKmH = 48.0, accuracyM = accuracy)

    @After
    fun tearDown() = TripLocation.clear()

    @Test
    fun returnsTheLatestRecentFix() {
        TripLocation.record(fix())
        assertEquals(52.5200, TripLocation.fixFor(now)!!.latitude, 1e-9)
    }

    @Test
    fun dropsFixesOlderThanTheStalenessBound() {
        TripLocation.record(fix(at = now.minusSeconds(11)))
        assertNull(TripLocation.fixFor(now))
    }

    @Test
    fun toleratesAClockSkewOfAFewSeconds() {
        TripLocation.record(fix(at = now.plusSeconds(1)))
        assertTrue(TripLocation.fixFor(now) != null)
    }

    @Test
    fun dropsImpreciseFixes() {
        TripLocation.record(fix(accuracy = 250f))
        assertNull(TripLocation.fixFor(now))
    }

    @Test
    fun rejectsNullIslandAndOutOfRangeCoordinates() {
        assertFalse(fix(latitude = 0.0, longitude = 0.0).hasValidCoordinate)
        assertFalse(fix(latitude = 91.0).hasValidCoordinate)
        assertTrue(fix().hasValidCoordinate)

        TripLocation.record(fix(latitude = 0.0, longitude = 0.0))
        assertNull(TripLocation.fixFor(now))
    }

    @Test
    fun recordingFlagFollowsTheService() {
        assertFalse(TripLocation.isRecording.value)
        TripLocation.markRecording(true)
        assertTrue(TripLocation.isRecording.value)
        TripLocation.clear()
        assertFalse(TripLocation.isRecording.value)
        assertNull(TripLocation.latest.value)
    }
}
