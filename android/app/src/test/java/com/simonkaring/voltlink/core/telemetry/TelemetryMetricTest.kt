package com.simonkaring.voltlink.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TelemetryMetricTest {
    @Test
    fun `instant efficiency is zero below five kmh`() {
        val snapshot = TelemetrySnapshot(speedKmH = 4.0, powerKW = 20.0)
        assertEquals(0.0, TelemetryMetric.INSTANT_EFFICIENCY.value(snapshot), 0.001)
        val moving = snapshot.copy(speedKmH = 50.0)
        assertEquals(40.0, TelemetryMetric.INSTANT_EFFICIENCY.value(moving), 0.001)
    }

    @Test
    fun `regen power is positive only while moving and not charging`() {
        val regen = TelemetrySnapshot(speedKmH = 30.0, powerKW = -25.0)
        assertEquals(25.0, TelemetryMetric.REGEN_POWER.value(regen), 0.001)
        assertEquals(0.0, TelemetryMetric.REGEN_POWER.value(regen.copy(isCharging = true)), 0.001)
        assertEquals(0.0, TelemetryMetric.REGEN_POWER.value(regen.copy(speedKmH = 0.0)), 0.001)
    }

    @Test
    fun `derived availability expires with stale inputs`() {
        val now = Instant.parse("2026-10-25T10:00:00Z")
        val fresh = TelemetrySnapshot(
            timestamp = now,
            speedKmH = 50.0,
            speedUpdatedAt = now,
            powerKW = 10.0,
            powerUpdatedAt = now,
        )
        val live = TelemetryMetric.includingDerivedMetrics(setOf(TelemetryMetric.SPEED, TelemetryMetric.POWER))
        assertTrue(TelemetryMetric.INSTANT_EFFICIENCY.isAvailable(fresh, live))
        val stale = fresh.copy(speedUpdatedAt = now.minusSeconds(30))
        assertFalse(TelemetryMetric.INSTANT_EFFICIENCY.isAvailable(stale, live))
        assertTrue(TelemetryMetric.SPEED.isAvailable(stale, setOf(TelemetryMetric.SPEED)))
    }

    @Test
    fun `demo mode makes every profile metric available`() {
        val snapshot = TelemetrySnapshot()
        assertTrue(TelemetryMetric.STEERING_ANGLE.isAvailable(snapshot, emptySet(), isDemoMode = true))
        assertFalse(TelemetryMetric.STEERING_ANGLE.isAvailable(snapshot, emptySet(), isDemoMode = false))
    }

    @Test
    fun `including derived metrics requires speed and power`() {
        assertEquals(
            setOf(TelemetryMetric.SPEED, TelemetryMetric.POWER, TelemetryMetric.INSTANT_EFFICIENCY, TelemetryMetric.REGEN_POWER),
            TelemetryMetric.includingDerivedMetrics(setOf(TelemetryMetric.SPEED, TelemetryMetric.POWER)),
        )
        assertEquals(
            setOf(TelemetryMetric.SPEED),
            TelemetryMetric.includingDerivedMetrics(setOf(TelemetryMetric.SPEED, TelemetryMetric.INSTANT_EFFICIENCY)),
        )
    }
}
