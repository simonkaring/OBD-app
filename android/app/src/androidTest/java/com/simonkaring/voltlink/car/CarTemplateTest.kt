package com.simonkaring.voltlink.car

import android.content.Context
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.data.CarTileLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers the templates the car session serves: two tabs, the first configured tile as the hero
 * dial and the rest as rows, plus the charging tab's session readouts.
 *
 * This runs on a device because the dials are rendered bitmaps and the copy comes from app
 * resources. `VoltLinkCarScreen.onGetTemplate()` builds the same templates asserted here.
 */
@RunWith(AndroidJUnit4::class)
class CarTemplateTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val renderer = CarDialRenderer(sizePx = 96)
    private val supported = setOf(
        TelemetryMetric.SOC,
        TelemetryMetric.POWER,
        TelemetryMetric.SPEED,
        TelemetryMetric.BATTERY_TEMP,
    )
    private val driving = TelemetrySnapshot(
        speedKmH = 56.0,
        powerKW = 136.8,
        stateOfChargePct = 77.0,
        vehicleRangeKm = 312.0,
        batteryTempC = 24.0,
    )

    private fun telemetryTab(
        tiles: List<CarTileKind>,
        snapshot: TelemetrySnapshot = driving,
        storedCodes: Int? = null,
        liveMetrics: Set<TelemetryMetric> = supported,
    ): PaneTemplate = carTelemetryTab(
        context = context,
        snapshot = snapshot,
        liveMetrics = liveMetrics,
        isDemoMode = true,
        connection = BleConnectionState.DemoMode,
        supportedMetrics = supported,
        tiles = tiles,
        storedCodes = storedCodes,
        renderer = renderer,
    ) as PaneTemplate

    @Test
    fun theFirstTileBecomesTheHeroDial() {
        val tiles = supported.map { CarTileKind.Metric(it) }

        val template = telemetryTab(tiles)
        val pane = template.pane

        assertEquals(TelemetryMetric.SOC.displayName, template.header!!.title.toString())
        assertNotNull("the hero dial needs a picture", pane.image)
        val bitmap = pane.image!!.icon!!.bitmap
        assertNotNull("the hero dial needs a bitmap", bitmap)
        assertEquals("the dial keeps its requested size", 96, bitmap!!.width)
        // The disc behind the arc means the centre is drawn, not transparent.
        assertTrue("the hero dial rendered blank", bitmap.getPixel(48, 48) ushr 24 != 0)
    }

    @Test
    fun everyRemainingTileIsARow() {
        val tiles = TelemetryMetric.entries.take(CarTileLayout.MAX_TILES - 1)
            .map { CarTileKind.Metric(it) } + CarTileKind.Health

        val rows = telemetryTab(tiles, storedCodes = 2).pane.rows

        assertEquals(tiles.size - 1, rows.size)
        rows.forEachIndexed { index, row ->
            val tile = tiles[index + 1]
            assertEquals(
                "row $index title",
                when (tile) {
                    is CarTileKind.Metric -> tile.metric.displayName
                    CarTileKind.Health -> "Diagnostics"
                },
                row.title.toString(),
            )
            assertTrue("row $index has no value", row.texts.first().toString().isNotBlank())
        }
        assertEquals("2 stored codes", rows.last().texts.first().toString())
    }

    @Test
    fun rowsCarryTheDialReadingAndThePowerChip() {
        val tiles = listOf(
            CarTileKind.Metric(TelemetryMetric.SOC),
            CarTileKind.Metric(TelemetryMetric.POWER),
        )

        // Above 100 the phone dial drops the decimal, so the row reads 137 kW.
        assertEquals("137 kW · Draw", telemetryTab(tiles).pane.rows.single().texts.first().toString())
        assertEquals(
            "20 kW · Regen",
            telemetryTab(tiles, snapshot = driving.copy(powerKW = -20.0)).pane.rows.single()
                .texts.first().toString(),
        )
        assertEquals(
            "0 kW · Idle",
            telemetryTab(tiles, snapshot = driving.copy(powerKW = 0.0)).pane.rows.single()
                .texts.first().toString(),
        )
    }

    @Test
    fun anUnavailableMetricStillGetsARow() {
        val tiles = listOf(
            CarTileKind.Metric(TelemetryMetric.SOC),
            CarTileKind.Metric(TelemetryMetric.AUX_12V),
        )

        val row = telemetryTab(tiles, liveMetrics = emptySet()).pane.rows.single()

        assertEquals(TelemetryMetric.AUX_12V.displayName, row.title.toString())
        assertEquals("$CAR_PLACEHOLDER V", row.texts.first().toString())
    }

    @Test
    fun aHealthHeroShowsTheBadgeAndItsStatus() {
        val template = telemetryTab(listOf(CarTileKind.Health, CarTileKind.Metric(TelemetryMetric.SPEED)))

        assertEquals("Diagnostics", template.header!!.title.toString())
        assertNotNull("the badge needs a picture", template.pane.image)
        assertEquals("56 km/h", template.pane.rows.single().texts.first().toString())
    }

    @Test
    fun anEmptyLayoutStillBuildsATemplate() {
        val template = carTelemetryTab(
            context = context,
            snapshot = driving,
            liveMetrics = supported,
            isDemoMode = true,
            connection = BleConnectionState.DemoMode,
            supportedMetrics = supported,
            tiles = emptyList(),
            storedCodes = null,
            renderer = renderer,
        )

        assertTrue(template is MessageTemplate)
        assertTrue(
            "the empty car tab should explain itself",
            (template as MessageTemplate).message.toString().isNotBlank(),
        )
    }

    @Test
    fun theDefaultLayoutHasAHeroAndThreeRows() {
        val template = telemetryTab(CarTileLayout.default.tiles)

        assertEquals(4, CarTileLayout.default.tiles.size)
        assertEquals(3, template.pane.rows.size)
    }

    @Test
    fun theScreenIsATabTemplateOfTelemetryAndCharging() {
        val template = carTabTemplate(
            context = context,
            activeTabId = CAR_TAB_TELEMETRY,
            content = telemetryTab(CarTileLayout.default.tiles),
            onTabSelected = {},
        )

        assertEquals(2, template.tabs.size)
        assertEquals("Telemetry", template.tabs[0].title.toString())
        assertEquals(CAR_TAB_TELEMETRY, template.tabs[0].contentId)
        assertEquals("Charging", template.tabs[1].title.toString())
        assertEquals(CAR_TAB_CHARGING, template.tabs[1].contentId)
        assertEquals(CAR_TAB_TELEMETRY, template.activeTabContentId)
        assertNotNull("the tab bar needs the app icon", template.headerAction)
        assertNotNull("every tab needs an icon", template.tabs[1].icon)
        assertTrue(template.tabContents!!.template is PaneTemplate)
    }

    @Test
    fun theChargingTabShowsTheLiveSession() {
        val charging = CarChargingState(
            isCharging = true,
            targetPercent = 80,
            secondsToTarget = 1860.0,
            deliveredKWh = 12.4,
            sessionStartSocPct = 40.0,
        )

        val template = carChargingTab(
            context = context,
            snapshot = driving.copy(isCharging = true, chargePowerKW = 61.8),
            liveMetrics = supported,
            isDemoMode = true,
            connection = BleConnectionState.DemoMode,
            supportedMetrics = supported,
            charging = charging,
            renderer = renderer,
        )

        assertEquals("State of Charge", template.header!!.title.toString())
        assertNotNull("the charging hero needs a dial", template.pane.image)
        val rows = template.pane.rows
        assertEquals(3, rows.size)
        assertEquals("Charge power", rows[0].title.toString())
        assertEquals("61.8 kW · Charging", rows[0].texts.first().toString())
        assertEquals("Time to 80%", rows[1].title.toString())
        assertEquals("31 min", rows[1].texts.first().toString())
        assertEquals("Energy delivered", rows[2].title.toString())
        assertEquals("12.4 kWh", rows[2].texts.first().toString())
    }

    @Test
    fun anIdleChargingTabSaysSo() {
        val template = carChargingTab(
            context = context,
            snapshot = driving,
            liveMetrics = supported,
            isDemoMode = true,
            connection = BleConnectionState.DemoMode,
            supportedMetrics = supported,
            charging = CarChargingState(targetPercent = 90),
            renderer = renderer,
        )

        val rows: List<Row> = template.pane.rows
        assertEquals("$CAR_PLACEHOLDER kW · Not charging", rows[0].texts.first().toString())
        assertEquals("Time to 90%", rows[1].title.toString())
        assertEquals(CAR_PLACEHOLDER, rows[1].texts.first().toString())
        assertEquals("0.0 kWh", rows[2].texts.first().toString())
    }
}
