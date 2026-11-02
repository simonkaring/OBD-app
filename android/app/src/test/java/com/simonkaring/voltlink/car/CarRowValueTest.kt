package com.simonkaring.voltlink.car

import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import org.junit.Assert.assertEquals
import org.junit.Test

class CarRowValueTest {
    private val snapshot = TelemetrySnapshot(
        speedKmH = 42.0,
        powerKW = 58.5,
        stateOfChargePct = 64.0,
        vehicleRangeKm = 210.0,
        batteryTempC = 31.5,
    )
    private val summary = CarTelemetrySummary.of(
        snapshot = snapshot,
        isDemoMode = false,
        connection = BleConnectionState.Ready("Vgate"),
    )

    @Test
    fun `driving rows reuse the summary strings`() {
        assertEquals(summary.stateOfCharge, carRowValue(CarTileKind.Metric(TelemetryMetric.SOC), summary, snapshot, null))
        assertEquals(summary.power, carRowValue(CarTileKind.Metric(TelemetryMetric.POWER), summary, snapshot, null))
        assertEquals(summary.speed, carRowValue(CarTileKind.Metric(TelemetryMetric.SPEED), summary, snapshot, null))
        assertEquals(summary.range, carRowValue(CarTileKind.Metric(TelemetryMetric.VEHICLE_RANGE), summary, snapshot, null))
    }

    @Test
    fun `other metrics format from the snapshot with their own unit`() {
        assertEquals(
            "32 °C",
            carRowValue(CarTileKind.Metric(TelemetryMetric.BATTERY_TEMP), summary, snapshot, null),
        )
    }

    @Test
    fun `health row reports the last scan instead of telemetry`() {
        assertEquals("Not scanned", carRowValue(CarTileKind.Health, summary, snapshot, null))
        assertEquals("No stored codes", carRowValue(CarTileKind.Health, summary, snapshot, 0))
        assertEquals("3 stored codes", carRowValue(CarTileKind.Health, summary, snapshot, 3))
    }
}
