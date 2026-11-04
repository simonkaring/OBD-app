package com.simonkaring.voltlink.car

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CarDialsTest {
    private val snapshot = TelemetrySnapshot(
        speedKmH = 42.0,
        powerKW = 58.5,
        stateOfChargePct = 64.0,
        vehicleRangeKm = 210.0,
        batteryTempC = 31.5,
    )

    @Test
    fun `a one-way dial fills by the metric's own range`() {
        val dial = carDial(TelemetryMetric.SOC, snapshot)

        assertEquals("64", dial.valueText)
        assertEquals("%", dial.unitText)
        assertEquals(0.64, dial.fraction, 0.0001)
        assertTrue(dial.available)
        assertFalse(dial.bidirectional)
        assertEquals(CarDialColors.soc, dial.colors)
    }

    @Test
    fun `power fills both ways and turns green under regen`() {
        val draw = carDial(TelemetryMetric.POWER, snapshot)
        assertEquals("58.5", draw.valueText)
        assertEquals(58.5 / 150.0, draw.fraction, 0.0001)
        assertTrue(draw.bidirectional)
        assertFalse(draw.negative)
        assertEquals(CarDialColors.power, draw.colors)

        val regen = carDial(TelemetryMetric.POWER, snapshot.copy(powerKW = -30.0))
        assertEquals(-30.0 / 50.0, regen.fraction, 0.0001)
        assertTrue(regen.negative)
        assertEquals(CarDialColors.regen, regen.colors)
    }

    @Test
    fun `hundreds drop the decimal like the phone dial`() {
        assertEquals("137", carDial(TelemetryMetric.POWER, snapshot.copy(powerKW = 136.8)).valueText)
        assertEquals("31.5", carDial(TelemetryMetric.BATTERY_TEMP, snapshot).valueText)
    }

    @Test
    fun `an unavailable metric reads as a placeholder with no arc`() {
        val dial = carDial(TelemetryMetric.AUX_12V, snapshot, available = false)

        assertEquals(CAR_PLACEHOLDER, dial.valueText)
        assertEquals(0.0, dial.fraction, 0.0001)
        assertFalse(dial.available)
    }

    @Test
    fun `a low state of charge uses the warning gradient`() {
        assertEquals(
            CarDialColors.socLow,
            carDial(TelemetryMetric.SOC, snapshot.copy(stateOfChargePct = 12.0)).colors,
        )
    }

    @Test
    fun `charge power fills the dial only while charging`() {
        val idle = carChargePowerDial(0.0, isCharging = false)
        assertFalse(idle.available)
        assertEquals(CAR_PLACEHOLDER, idle.valueText)
        assertEquals(0.0, idle.fraction, 0.0001)

        val charging = carChargePowerDial(61.8, isCharging = true)
        assertTrue(charging.available)
        assertEquals("61.8", charging.valueText)
        assertEquals("kW", charging.unitText)
        assertEquals(61.8 / 150.0, charging.fraction, 0.0001)
    }

    @Test
    fun `time to target dial shows the remaining time over the session progress`() {
        val charging = CarChargingState(
            isCharging = true,
            targetPercent = 80,
            secondsToTarget = 1860.0,
            sessionStartSocPct = 40.0,
        )

        val dial = carTimeToTargetDial(charging, socPct = 64.0, reachedText = "Reached")

        assertEquals("31 min", dial.valueText)
        assertNull(dial.unitText)
        assertEquals(0.6, dial.fraction, 0.0001)
        assertTrue(dial.available)
    }

    @Test
    fun `time to target dial reports the reached and idle states`() {
        val reached = carTimeToTargetDial(
            CarChargingState(isCharging = true, secondsToTarget = 0.0),
            socPct = 80.0,
            reachedText = "Reached",
        )
        assertEquals("Reached", reached.valueText)

        val idle = carTimeToTargetDial(CarChargingState(), socPct = 64.0, reachedText = "Reached")
        assertEquals(CAR_PLACEHOLDER, idle.valueText)
        assertFalse(idle.available)
        assertEquals(0.0, idle.fraction, 0.0001)
    }

    @Test
    fun `the pack bar follows the phone's colour rules`() {
        assertEquals(CarDialColors.cyan, carBarColor(64.0, isCharging = false))
        assertEquals(CarDialColors.amber, carBarColor(30.0, isCharging = false))
        assertEquals(CarDialColors.red, carBarColor(12.0, isCharging = false))
        assertEquals(CarDialColors.green, carBarColor(12.0, isCharging = true))
        assertEquals(CarDialColors.textSecondary, carBarColor(null, isCharging = false))
    }

    @Test
    fun `the pack bar shows a rounded percentage and clamps its fill`() {
        val bar = carSocBar("HV", trailing = null, socPct = 77.6, isCharging = false, marks = listOf(0.8))

        assertEquals("78%", bar.valueText)
        assertEquals(0.776, bar.fraction, 0.0001)
        assertTrue(bar.available)
        assertEquals(listOf(0.8), bar.marks)
        assertEquals(1.0, carSocBar("HV", null, 140.0, false).fraction, 0.0001)
    }

    @Test
    fun `an unknown state of charge leaves the bar empty with a dash`() {
        val bar = carSocBar("HV", trailing = null, socPct = null, isCharging = false)

        assertEquals("—", bar.valueText)
        assertEquals(0.0, bar.fraction, 0.0001)
        assertFalse(bar.available)
    }

    @Test
    fun `a dashboard is empty only without a bar and dials`() {
        assertTrue(CarDashboard().isEmpty)
        assertFalse(CarDashboard(bar = carSocBar("HV", null, 50.0, false)).isEmpty)
        assertFalse(CarDashboard(dials = listOf(carDial(TelemetryMetric.SPEED, snapshot))).isEmpty)
    }

    @Test
    fun `durations keep the phone's hour and minute wording`() {
        assertEquals("30 min", carDurationText(1800.0))
        assertEquals("1 h 5 min", carDurationText(3900.0))
        assertEquals("1 min", carDurationText(10.0))
    }

    @Test
    fun `the health tile keeps its wording without a scan`() {
        assertEquals("Not scanned", defaultHealthText(null))
        assertEquals("No stored codes", defaultHealthText(0))
        assertEquals("3 stored codes", defaultHealthText(3))
    }
}
