package com.simonkaring.voltlink.ui

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.DistanceUnit
import org.junit.Assert.assertEquals
import org.junit.Test

class UnitPrefsTest {
    private val consumption = 18.5

    @Test
    fun `consumption stays per hundred kilometres in metric`() {
        val units = UnitPrefs()

        assertEquals("kWh/100km", units.efficiencyUnitLabel)
        assertEquals(consumption, units.efficiencyValue(consumption), 1e-9)
    }

    @Test
    fun `consumption follows the distance unit`() {
        val units = UnitPrefs(distance = DistanceUnit.MILES)

        assertEquals("kWh/100mi", units.efficiencyUnitLabel)
        assertEquals(29.77, units.efficiencyValue(consumption), 0.01)
    }

    @Test
    fun `the dashboard tile converts the same way`() {
        val snapshot = TelemetrySnapshot(tripAverageConsumption = consumption)
        val units = UnitPrefs(distance = DistanceUnit.MILES)

        assertEquals("kWh/100mi", units.unit(TelemetryMetric.TRIP_AVERAGE_CONSUMPTION))
        assertEquals(29.77, units.value(TelemetryMetric.TRIP_AVERAGE_CONSUMPTION, snapshot), 0.01)
    }
}
