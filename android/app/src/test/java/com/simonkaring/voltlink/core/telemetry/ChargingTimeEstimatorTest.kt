package com.simonkaring.voltlink.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChargingTimeEstimatorTest {
    @Test
    fun `ac charging holds its rate`() {
        // 10 % of a 66.5 kWh pack at 11 kW = 6.65 kWh / 11 kW = 0.6045 h
        val seconds = ChargingTimeEstimator.secondsToTarget(
            currentSoc = 40.0,
            targetSoc = 50.0,
            currentPowerKW = 11.0,
            capacityKWh = 66.5,
        )
        assertEquals(0.6045 * 3600, seconds!!, 1.0)
    }

    @Test
    fun `target already reached costs nothing`() {
        assertEquals(
            0.0,
            ChargingTimeEstimator.secondsToTarget(85.0, 80.0, 50.0, 66.5)!!,
            1e-9,
        )
    }

    @Test
    fun `unusable inputs return null`() {
        assertNull(ChargingTimeEstimator.secondsToTarget(50.0, 80.0, 0.0, 66.5))
        assertNull(ChargingTimeEstimator.secondsToTarget(50.0, 80.0, 40.0, 0.0))
        assertNull(ChargingTimeEstimator.secondsToTarget(-5.0, 80.0, 40.0, 66.5))
    }

    @Test
    fun `dc taper makes the last stretch slower than a flat rate`() {
        val flat = 66.5 * 0.20 / 80.0 * 3600 // 20 % at a constant 80 kW
        val estimated = ChargingTimeEstimator.secondsToTarget(
            currentSoc = 80.0,
            targetSoc = 100.0,
            currentPowerKW = 80.0,
            capacityKWh = 66.5,
        )!!
        assertTrue("expected taper beyond a flat-rate estimate", estimated > flat * 1.2)
    }

    @Test
    fun `observed falling curve projects a lower rate`() {
        val curve = listOf(
            ChargingCurveSample(50.0, 100.0),
            ChargingCurveSample(60.0, 92.0),
            ChargingCurveSample(70.0, 82.0),
            ChargingCurveSample(78.0, 68.0),
        )
        val slope = ChargingTimeEstimator.observedTaperSlope(curve)
        // (68 - 82) / (78 - 70) = -1.75 kW per percent
        assertEquals(-1.75, slope!!, 1e-9)
        val projected = ChargingTimeEstimator.projectedPowerKW(90.0, 78.0, 68.0, curve)
        assertTrue(projected < 68.0)
    }

    @Test
    fun `flat or rising curve is not treated as a taper`() {
        assertNull(ChargingTimeEstimator.observedTaperSlope(listOf(ChargingCurveSample(40.0, 50.0), ChargingCurveSample(60.0, 50.0))))
        assertNull(ChargingTimeEstimator.observedTaperSlope(listOf(ChargingCurveSample(40.0, 50.0), ChargingCurveSample(60.0, 60.0))))
    }
}
