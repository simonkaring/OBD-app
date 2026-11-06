package com.simonkaring.voltlink.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TripMathTest {
    private fun advance(
        distanceKm: Double = 0.0,
        kWhUsed: Double = 0.0,
        kWhRecovered: Double = 0.0,
        energyComplete: Boolean = true,
        intervalSeconds: Double = 1.0,
        speedKmH: Double = 0.0,
        powerKW: Double = 0.0,
        hasFreshSpeed: Boolean = true,
        hasFreshPower: Boolean = true,
        hasPowerData: Boolean = true,
        isCharging: Boolean = false,
    ): TripMath.Progress = TripMath.advance(
        distanceKm = distanceKm,
        kWhUsed = kWhUsed,
        kWhRecovered = kWhRecovered,
        energyComplete = energyComplete,
        intervalSeconds = intervalSeconds,
        speedKmH = speedKmH,
        powerKW = powerKW,
        hasFreshSpeed = hasFreshSpeed,
        hasFreshPower = hasFreshPower,
        hasPowerData = hasPowerData,
        isCharging = isCharging,
    )

    @Test
    fun `a fresh speed interval adds the distance driven`() {
        val progress = advance(speedKmH = 60.0, intervalSeconds = 60.0)

        assertEquals(1.0, progress.distanceKm, 1e-9)
    }

    @Test
    fun `a stale speed adds no distance`() {
        val progress = advance(
            distanceKm = 5.0,
            speedKmH = 60.0,
            intervalSeconds = 60.0,
            hasFreshSpeed = false,
        )

        assertEquals(5.0, progress.distanceKm, 1e-9)
    }

    @Test
    fun `a stale power adds no energy and marks the trip incomplete`() {
        val progress = advance(
            kWhUsed = 2.0,
            powerKW = 11.0,
            intervalSeconds = 60.0,
            hasFreshPower = false,
        )

        assertEquals(2.0, progress.kWhUsed, 1e-9)
        assertFalse(progress.energyComplete)
    }

    @Test
    fun `a profile without power data leaves the trip incomplete`() {
        val progress = advance(hasPowerData = false, intervalSeconds = 60.0)

        assertFalse(progress.energyComplete)
    }

    @Test
    fun `regen is only counted while the car is moving`() {
        val moving = advance(powerKW = -20.0, speedKmH = 50.0, intervalSeconds = 60.0)
        assertEquals(1.0 / 3.0, moving.kWhRecovered, 1e-9)

        val parked = advance(powerKW = -20.0, speedKmH = 0.0, intervalSeconds = 60.0)
        assertEquals(0.0, parked.kWhRecovered, 1e-9)
    }

    @Test
    fun `charging power is not trip energy`() {
        val progress = advance(powerKW = 11.0, intervalSeconds = 60.0, isCharging = true)

        assertEquals(0.0, progress.kWhUsed, 1e-9)
        assertTrue(progress.energyComplete)
    }

    @Test
    fun `a gap longer than five minutes marks the energy incomplete`() {
        val progress = advance(distanceKm = 3.0, speedKmH = 60.0, intervalSeconds = 600.0)

        assertEquals(3.0, progress.distanceKm, 1e-9)
        assertFalse(progress.energyComplete)
    }

    @Test
    fun `a non-positive interval changes nothing`() {
        val progress = advance(distanceKm = 3.0, speedKmH = 100.0, intervalSeconds = 0.0)

        assertEquals(3.0, progress.distanceKm, 1e-9)
        assertTrue(progress.energyComplete)
    }
}
