package com.simonkaring.voltlink.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class ChargingSessionMathTest {
    private val start = Instant.parse("2026-10-24T10:00:00Z")

    @Test
    fun `average power is energy over elapsed time`() {
        // 28 kWh in 40 minutes is 42 kW, the number the charger also shows.
        val average = ChargingSessionMath.averagePowerKW(28.0, start, start.plusSeconds(2_400))
        assertEquals(42.0, average!!, 0.001)
    }

    @Test
    fun `taper samples do not drag the average down`() {
        // 55 kWh over a full hour of a session that spent most updates in the taper.
        val average = ChargingSessionMath.averagePowerKW(55.0, start, start.plusSeconds(3_600))
        assertEquals(55.0, average!!, 0.001)
    }

    @Test
    fun `no average without elapsed time or finite energy`() {
        assertNull(ChargingSessionMath.averagePowerKW(10.0, start, start))
        assertNull(ChargingSessionMath.averagePowerKW(10.0, start, start.plusSeconds(5)))
        assertNull(ChargingSessionMath.averagePowerKW(Double.NaN, start, start.plusSeconds(600)))
        assertNull(ChargingSessionMath.averagePowerKW(Double.POSITIVE_INFINITY, start, start.plusSeconds(600)))
    }
}
