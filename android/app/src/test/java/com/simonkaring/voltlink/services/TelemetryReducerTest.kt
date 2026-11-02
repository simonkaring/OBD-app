package com.simonkaring.voltlink.services

import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TelemetryReducerTest {
    private val base = Instant.parse("2026-10-25T10:00:00Z")

    @Test
    fun `rejects implausible values`() {
        val reducer = TelemetryReducer(66.5)
        assertFalse(reducer.apply(TelemetryUpdate.Speed(500.0), base))
        assertFalse(reducer.apply(TelemetryUpdate.Soc(140.0), base))
        assertEquals(0.0, reducer.snapshot.speedKmH, 0.001)
    }

    @Test
    fun `combines fresh pack voltage and current into power`() {
        val reducer = TelemetryReducer(66.5)
        assertTrue(reducer.apply(TelemetryUpdate.PackVoltage(400.0), base))
        assertTrue(reducer.apply(TelemetryUpdate.PackCurrent(50.0), base.plusSeconds(1)))
        assertEquals(20.0, reducer.snapshot.powerKW, 0.001)
        assertTrue(TelemetryMetric.POWER in reducer.liveMetrics)
        assertEquals(400.0, reducer.snapshot.voltageV, 0.001)
    }

    @Test
    fun `negative current is charging only when stationary`() {
        val reducer = TelemetryReducer(66.5)
        reducer.apply(TelemetryUpdate.Speed(0.0), base)
        reducer.apply(TelemetryUpdate.PackVoltage(400.0), base)
        reducer.apply(TelemetryUpdate.PackCurrent(-100.0), base.plusSeconds(1))
        assertTrue(reducer.snapshot.isCharging)
        assertEquals(40.0, reducer.snapshot.chargePowerKW, 0.001)

        val moving = TelemetryReducer(66.5)
        moving.apply(TelemetryUpdate.Speed(40.0), base)
        moving.apply(TelemetryUpdate.PackVoltage(400.0), base)
        moving.apply(TelemetryUpdate.PackCurrent(-100.0), base.plusSeconds(1))
        assertFalse(moving.snapshot.isCharging)
    }

    @Test
    fun `moving clears a stale charging estimate`() {
        val reducer = TelemetryReducer(66.5)
        reducer.apply(TelemetryUpdate.Soc(50.0), base)
        reducer.apply(TelemetryUpdate.Soc(51.0), base.plusSeconds(60))
        reducer.apply(TelemetryUpdate.Speed(30.0), base.plusSeconds(61))
        assertFalse(reducer.snapshot.isCharging)
        assertEquals(0.0, reducer.snapshot.chargePowerKW, 0.001)
    }

    @Test
    fun `derived metrics appear only with their inputs`() {
        val reducer = TelemetryReducer(66.5)
        reducer.apply(TelemetryUpdate.Speed(80.0), base)
        assertFalse(TelemetryMetric.INSTANT_EFFICIENCY in reducer.liveMetrics)
        reducer.apply(TelemetryUpdate.Power(400.0, 25.0, 10.0), base)
        assertTrue(TelemetryMetric.INSTANT_EFFICIENCY in reducer.liveMetrics)
        assertTrue(TelemetryMetric.REGEN_POWER in reducer.liveMetrics)
    }

    @Test
    fun `external speed only wins when obd speed is stale`() {
        val reducer = TelemetryReducer(66.5)
        val now = Instant.now()
        reducer.apply(TelemetryUpdate.Speed(60.0), now.minusSeconds(20))
        assertFalse(reducer.needsExternalSpeed(now.minusSeconds(5)))
        assertTrue(reducer.needsExternalSpeed(now))
        reducer.applyExternalSpeed(42.0, now)
        assertEquals(42.0, reducer.snapshot.speedKmH, 0.001)
        reducer.clearExternalSpeed()
        assertEquals(0.0, reducer.snapshot.speedKmH, 0.001)
    }

    @Test
    fun `community metrics accumulate in the snapshot`() {
        val reducer = TelemetryReducer(66.5)
        reducer.apply(TelemetryUpdate.CommunityMetric(TelemetryMetric.STEERING_ANGLE, 12.5), base)
        reducer.apply(TelemetryUpdate.CommunityMetric(TelemetryMetric.MOTOR_TEMP, 61.0), base)
        assertEquals(12.5, reducer.snapshot.communityValues?.get(TelemetryMetric.STEERING_ANGLE) ?: 0.0, 0.001)
        assertEquals(61.0, reducer.snapshot.communityValues?.get(TelemetryMetric.MOTOR_TEMP) ?: 0.0, 0.001)
    }

    @Test
    fun `soc slope estimates charging power after thirty seconds`() {
        val reducer = TelemetryReducer(50.0)
        // A parked car with SoC polling every 10 s: 0.5 % of 50 kWh over 60 s = 15 kW.
        reducer.apply(TelemetryUpdate.Speed(0.0), base)
        for (step in 0..6) {
            val at = base.plusSeconds(step * 10L)
            reducer.apply(TelemetryUpdate.Speed(0.0), at)
            reducer.apply(TelemetryUpdate.Soc(40.0 + step * 0.1), at)
        }
        assertTrue(reducer.snapshot.isCharging)
        assertEquals(18.0, reducer.snapshot.chargePowerKW, 1.0)
    }
}
