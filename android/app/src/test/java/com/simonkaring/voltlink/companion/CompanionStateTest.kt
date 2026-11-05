package com.simonkaring.voltlink.companion

import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.ChargePowerSource
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.services.ChargingTracker
import com.simonkaring.voltlink.services.TripTracker
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class CompanionStateTest {
    private val now = Instant.parse("2026-11-05T12:00:00Z")
    private val metrics = setOf(TelemetryMetric.SOC, TelemetryMetric.POWER, TelemetryMetric.SPEED)
    private val snapshot = TelemetrySnapshot(
        timestamp = now, stateOfChargePct = 60.0, socUpdatedAt = now,
        powerKW = -20.0, powerUpdatedAt = now, speedKmH = 50.0, speedUpdatedAt = now,
    )

    private fun frame(
        snapshot: TelemetrySnapshot = this.snapshot,
        live: Set<TelemetryMetric> = metrics,
        supported: Set<TelemetryMetric> = metrics,
        connection: BleConnectionState = BleConnectionState.Ready("test"),
        capacity: Double = 60.0,
        trip: TripTracker.State = TripTracker.State(),
        charging: ChargingTracker.State = ChargingTracker.State(),
        price: Double = 2.5,
        demo: Boolean = false,
    ) = companionState(snapshot, live, supported, connection, demo, capacity, trip, charging, price, now)

    @Test fun `disconnection hides old readings even in demo mode`() {
        val state = frame(connection = BleConnectionState.Disconnected, demo = true)
        assertTrue(state.metrics.isEmpty())
        assertNull(state.rangeKm)
        assertEquals(CompanionCharging.DISCONNECTED, state.charging)
    }

    @Test fun `silent upstream expires against wall clock`() {
        val state = frame(snapshot = snapshot.copy(timestamp = now.minusSeconds(16)))
        assertEquals(CompanionConnection.STALE, state.connection)
        assertTrue(state.metrics.isEmpty())
    }

    @Test fun `each timestamped signal expires independently`() {
        val state = frame(snapshot = snapshot.copy(socUpdatedAt = now.minusSeconds(16), powerUpdatedAt = now.plusSeconds(1)))
        assertEquals(mapOf(TelemetryMetric.SPEED to 50.0), state.metrics)
    }

    @Test fun `unsupported signals and never received defaults are hidden`() {
        assertFalse(TelemetryMetric.POWER in frame(supported = setOf(TelemetryMetric.SOC)).metrics)
        assertTrue(frame(live = emptySet()).metrics.isEmpty())
    }

    @Test fun `range needs actual trip average and known profile capacity`() {
        val trip = TripTracker.State(current = TripRecord(), averageConsumption = 20.0)
        assertNull(frame().rangeKm)
        assertEquals(180.0, frame(trip = trip).rangeKm!!, 0.001)
        assertNull(frame(trip = trip, capacity = 0.0).rangeKm)
    }

    @Test fun `regen retains its sign and is not called charging`() {
        val state = frame()
        assertEquals(-20.0, state.metrics[TelemetryMetric.POWER]!!, 0.0)
        assertNotEquals(CompanionCharging.ACTIVE, state.charging)
    }

    @Test fun `charging reuses estimator session counters and DKK tariff`() {
        val charge = snapshot.copy(isCharging = true, chargePowerKW = 60.0,
            chargePowerUpdatedAt = now, chargePowerSource = ChargePowerSource.MEASURED)
        val tracker = ChargingTracker.State(isCharging = true, targetPercent = 100.0,
            current = ChargingSessionRecord(startTime = now.minusSeconds(600), totalKWhDelivered = 10.0))
        val state = frame(snapshot = charge, charging = tracker)
        assertEquals(CompanionCharging.ACTIVE, state.charging)
        assertEquals(720.0, state.secondsTo80!!, 0.01)
        assertEquals(25.0, state.costDKK!!, 0.0)
        assertEquals(600L, state.chargingSeconds)
        assertNull(frame(snapshot = charge, charging = tracker, capacity = 0.0).secondsTo80)
        assertNull(frame(snapshot = charge, charging = tracker, price = Double.NaN).costDKK)
    }

    @Test fun `stale charge power never produces active state or ETA`() {
        val charge = snapshot.copy(isCharging = true, chargePowerKW = 60.0,
            chargePowerUpdatedAt = now.minusSeconds(16), chargePowerSource = ChargePowerSource.MEASURED)
        val state = frame(snapshot = charge, charging = ChargingTracker.State(isCharging = true))
        assertEquals(CompanionCharging.UNAVAILABLE, state.charging)
        assertNull(state.chargePowerKW)
        assertNull(state.secondsTo80)
    }

    @Test fun `target reached is not inferred from a zero power default`() {
        assertEquals(CompanionCharging.UNAVAILABLE, frame().charging)
        val stopped = snapshot.copy(chargePowerKW = 0.0, chargePowerUpdatedAt = now,
            chargePowerSource = ChargePowerSource.MEASURED, stateOfChargePct = 80.0)
        val tracker = ChargingTracker.State(lastCompletedTargetReached = true)
        assertEquals(CompanionCharging.COMPLETE, frame(snapshot = stopped, charging = tracker).charging)
        assertEquals(CompanionCharging.INACTIVE, frame(snapshot = stopped.copy(stateOfChargePct = 60.0), charging = tracker).charging)
    }
}
