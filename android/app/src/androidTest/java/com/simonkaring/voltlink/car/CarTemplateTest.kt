package com.simonkaring.voltlink.car

import android.content.Context
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.data.CarTileLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers the template the car session serves: every configured row has to arrive as a list item
 * with a title and a value, all the way up to [CarTileLayout.MAX_TILES] rows.
 *
 * This runs on a device because the health row and the template title come from the app
 * resources. `VoltLinkCarScreen.onGetTemplate()` delegates to the same [carTelemetryTemplate]
 * call asserted here.
 */
@RunWith(AndroidJUnit4::class)
class CarTemplateTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private val driving = TelemetrySnapshot(
        speedKmH = 56.0,
        powerKW = 136.8,
        stateOfChargePct = 77.0,
        vehicleRangeKm = 312.0,
        aux12VVolts = 13.4,
        batteryTempC = 24.0,
        tripAverageConsumption = 17.5,
    )

    private fun template(
        tiles: List<CarTileKind>,
        storedCodes: Int? = null,
        isDemoMode: Boolean = true,
    ): ListTemplate = carTelemetryTemplate(
        context = context,
        snapshot = driving,
        isDemoMode = isDemoMode,
        connection = if (isDemoMode) BleConnectionState.DemoMode else BleConnectionState.Ready("iCar Pro"),
        tiles = tiles,
        storedCodes = storedCodes,
    )

    private fun rows(tiles: List<CarTileKind>, storedCodes: Int? = null): List<Row> =
        template(tiles, storedCodes).singleList!!.items.map { it as Row }

    @Test
    fun everyConfiguredRowReachesTheCarAsAListItem() {
        // Seven metrics plus the health row: the whole budget, twice what a pane renders.
        val tiles = TelemetryMetric.entries.take(CarTileLayout.MAX_TILES - 1)
            .map { CarTileKind.Metric(it) } + CarTileKind.Health
        assertEquals(CarTileLayout.MAX_TILES, tiles.size)

        val carRows = rows(tiles, storedCodes = 2)
        assertEquals(tiles.size, carRows.size)
        tiles.forEachIndexed { index, tile ->
            assertTrue("row $index is missing its title", carRows[index].title.toString().isNotBlank())
            assertEquals("row $index should carry one value", 1, carRows[index].texts.size)
            assertTrue("row $index is missing its value", carRows[index].texts.first().toString().isNotBlank())
        }
        assertEquals("Diagnostics", carRows.last().title.toString())
        assertEquals("2 stored codes", carRows.last().texts.first().toString())
    }

    @Test
    fun everyMetricHasATitleAndAValue() {
        TelemetryMetric.entries.forEach { metric ->
            val row = rows(listOf(CarTileKind.Metric(metric))).single()
            assertEquals(metric.displayName, row.title.toString())
            assertTrue("${metric.name} has no value", row.texts.single().toString().isNotBlank())
        }
    }

    @Test
    fun healthRowReportsTheLastScan() {
        assertEquals("Not scanned", rows(listOf(CarTileKind.Health)).single().texts.single().toString())
        assertEquals(
            "No stored codes",
            rows(listOf(CarTileKind.Health), storedCodes = 0).single().texts.single().toString(),
        )
        assertEquals(
            "7 stored codes",
            rows(listOf(CarTileKind.Health), storedCodes = 7).single().texts.single().toString(),
        )
    }

    @Test
    fun theDefaultLayoutKeepsItsFourRows() {
        val default = CarTileLayout.default.tiles
        assertEquals(4, rows(default).size)
        assertTrue(template(default).header?.title.toString().contains("Demo"))
    }

    @Test
    fun anEmptyLayoutStillBuildsATemplate() {
        assertTrue(template(emptyList()).singleList!!.items.isEmpty())
    }
}
