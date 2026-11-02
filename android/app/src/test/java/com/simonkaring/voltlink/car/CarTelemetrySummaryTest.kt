package com.simonkaring.voltlink.car

import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class CarTelemetrySummaryTest {
    private val snapshot = TelemetrySnapshot(
        speedKmH = 74.4,
        powerKW = 22.5,
        stateOfChargePct = 63.2,
        vehicleRangeKm = 287.4,
    )

    @Test
    fun formatsTheDrivingPane() {
        val summary = CarTelemetrySummary.of(snapshot, isDemoMode = false, connection = BleConnectionState.Ready("Vgate iCar Pro"))

        assertEquals("VoltLink · Vgate iCar Pro", summary.title)
        assertEquals("63 %", summary.stateOfCharge)
        assertEquals("22.5 kW", summary.power)
        assertEquals("74 km/h", summary.speed)
        assertEquals("287 km", summary.range)
    }

    @Test
    fun showsChargePowerWhileCharging() {
        val charging = snapshot.copy(isCharging = true, chargePowerKW = 61.8)
        val summary = CarTelemetrySummary.of(charging, isDemoMode = true, connection = BleConnectionState.DemoMode)

        assertEquals("VoltLink · Demo", summary.title)
        assertEquals("61.8 kW", summary.power)
    }

    @Test
    fun fallsBackToPlaceholdersAndConnectionStates() {
        val empty = CarTelemetrySummary.of(TelemetrySnapshot(), isDemoMode = false, connection = BleConnectionState.Disconnected)
        assertEquals("VoltLink · No adapter", empty.title)
        assertEquals("—", empty.stateOfCharge)
        assertEquals("—", empty.power)
        assertEquals("—", empty.range)
        assertEquals("0 km/h", empty.speed)

        val offline = CarTelemetrySummary.of(
            snapshot,
            isDemoMode = false,
            connection = BleConnectionState.Error("Write failed"),
        )
        assertEquals("VoltLink · Adapter offline", offline.title)
    }
}
