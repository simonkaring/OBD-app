package com.simonkaring.voltlink.data

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CarTileLayoutTest {
    @Test
    fun `default rows cover the four driving values`() {
        assertEquals(
            listOf(
                CarTileKind.Metric(TelemetryMetric.SOC),
                CarTileKind.Metric(TelemetryMetric.POWER),
                CarTileKind.Metric(TelemetryMetric.SPEED),
                CarTileKind.Health,
            ),
            CarTileLayout.default.tiles,
        )
    }

    @Test
    fun `layout round trips through its stored json`() {
        val layout = CarTileLayout(
            listOf(
                CarTileKind.Metric(TelemetryMetric.BATTERY_TEMP),
                CarTileKind.Health,
                CarTileKind.Metric(TelemetryMetric.VEHICLE_RANGE),
            ),
        )

        assertEquals(layout, CarTileLayout.decode(layout.encode()))
    }

    @Test
    fun `stored layouts longer than the row limit are truncated`() {
        val tooMany = List(10) { index ->
            CarTileKind.Metric(TelemetryMetric.entries[index])
        }
        val decoded = CarTileLayout.decode(CarTileLayout(tooMany.take(CarTileLayout.MAX_TILES)).encode())

        assertEquals(CarTileLayout.MAX_TILES, decoded.tiles.size)
    }

    @Test
    fun `constructing beyond the cap is rejected`() {
        val outcome = runCatching { CarTileLayout(List(9) { CarTileKind.Health }) }

        assertTrue(outcome.isFailure)
    }

    @Test
    fun `corrupt storage falls back to the default`() {
        assertEquals(CarTileLayout.default, CarTileLayout.decode(null))
        assertEquals(CarTileLayout.default, CarTileLayout.decode("{"))
    }
}
