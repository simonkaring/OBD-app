package com.simonkaring.voltlink.car

import android.content.Context
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.data.CarTileLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers the templates the car session serves: two tabs, each a pane whose picture is the phone's
 * bar and dials and whose rows report the trip or charging session and the number readouts.
 *
 * This runs on a device because the dashboard is a rendered bitmap and the copy comes from app
 * resources. `VoltLinkCarScreen.onGetTemplate()` builds the same templates asserted here.
 */
@RunWith(AndroidJUnit4::class)
class CarTemplateTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val renderer = CarDashboardRenderer(sizePx = 96)
    private val supported = setOf(
        TelemetryMetric.SOC,
        TelemetryMetric.POWER,
        TelemetryMetric.SPEED,
        TelemetryMetric.BATTERY_TEMP,
        TelemetryMetric.AUX_12V,
    )
    private val driving = TelemetrySnapshot(
        speedKmH = 56.0,
        powerKW = 136.8,
        stateOfChargePct = 77.0,
        vehicleRangeKm = 312.0,
        batteryTempC = 24.0,
        aux12VVolts = 13.8,
        tripAverageConsumption = 14.2,
    )

    private fun telemetryTab(
        tiles: List<CarTileKind>,
        snapshot: TelemetrySnapshot = driving,
        storedCodes: Int? = null,
        liveMetrics: Set<TelemetryMetric> = supported,
        trip: CarTripState = CarTripState(),
    ): PaneTemplate = carTelemetryTab(
        context = context,
        snapshot = snapshot,
        liveMetrics = liveMetrics,
        isDemoMode = true,
        connection = BleConnectionState.DemoMode,
        supportedMetrics = supported,
        tiles = tiles,
        storedCodes = storedCodes,
        trip = trip,
        renderer = renderer,
    ) as PaneTemplate

    private fun rowTexts(template: PaneTemplate): List<Pair<String, String>> =
        template.pane.rows.map { it.title.toString() to it.texts.first().toString() }

    @Test
    fun theDashboardIsDrawnIntoThePanePicture() {
        val template = telemetryTab(CarTileLayout.default.tiles)

        assertEquals("Telemetry", template.header!!.title.toString())
        val bitmap = template.pane.image!!.icon!!.bitmap
        assertNotNull("the dashboard needs a bitmap", bitmap)
        assertEquals("the picture is square and keeps its requested size", 96, bitmap!!.width)
        assertEquals(96, bitmap.height)
        // Inside the left dial card, so a blank picture fails; the gap between cards is clear.
        assertTrue("the dashboard rendered blank", bitmap.getPixel(24, 56) ushr 24 != 0)
    }

    @Test
    fun anUnchangedDashboardReusesItsBitmap() {
        val dashboard = CarDashboard(bar = carSocBar("HV", null, 50.0, false))

        assertSame(renderer.icon(dashboard), renderer.icon(dashboard.copy()))
    }

    @Test
    fun theDefaultLayoutHasTheTripRowNumbersAndDiagnostics() {
        val template = telemetryTab(CarTileLayout.default.tiles, storedCodes = 2)

        assertEquals(
            listOf(
                "Trip not recording" to "Starts when the car moves",
                "Trip average" to "14.2 kWh/100km",
                "Auxiliary 12V" to "13.8 V",
                "Diagnostics" to "2 stored codes",
            ),
            rowTexts(template),
        )
        template.pane.rows.forEach { assertNotNull("every row needs a glyph", it.image) }
    }

    @Test
    fun aRecordingTripIsReportedOnTheTelemetryTab() {
        val template = telemetryTab(
            CarTileLayout.default.tiles,
            trip = CarTripState(isRecording = true, distanceKm = 12.44, durationSeconds = 1110),
        )

        val trip = template.pane.rows.first()
        assertEquals("Recording trip", trip.title.toString())
        assertEquals("12.4 km · 18 min", trip.texts.first().toString())
    }

    @Test
    fun anIdleTripSaysWhetherAutomaticTripsAreOn() {
        val manual = telemetryTab(CarTileLayout.default.tiles, trip = CarTripState(autoTrips = false))

        assertEquals("Automatic trips are off", manual.pane.rows.first().texts.first().toString())
    }

    @Test
    fun anUnavailableMetricStillGetsARow() {
        val tiles = listOf(CarTileKind.Metric(TelemetryMetric.SOC), CarTileKind.Metric(TelemetryMetric.AUX_12V))

        val rows = telemetryTab(tiles, liveMetrics = emptySet()).pane.rows

        assertEquals(TelemetryMetric.AUX_12V.displayName, rows[1].title.toString())
        assertEquals("$CAR_PLACEHOLDER V", rows[1].texts.first().toString())
    }

    @Test
    fun theSpeedAndPowerDialsAndTheBarStayOutOfTheRows() {
        val tiles = listOf(
            CarTileKind.Metric(TelemetryMetric.POWER),
            CarTileKind.Metric(TelemetryMetric.SPEED),
            CarTileKind.Metric(TelemetryMetric.SOC),
        )

        val template = telemetryTab(tiles)

        assertNotNull("the dials still need their picture", template.pane.image)
        assertEquals(listOf("Trip not recording"), template.pane.rows.map { it.title.toString() })
    }

    @Test
    fun aLayoutWithoutADialOrBarHasNoPicture() {
        val template = telemetryTab(listOf(CarTileKind.Health))

        assertNull(template.pane.image)
        assertEquals(listOf("Trip not recording", "Diagnostics"), template.pane.rows.map { it.title.toString() })
    }

    @Test
    fun thePaneNeverHoldsMoreRowsThanTheHostShows() {
        val tiles = TelemetryMetric.entries
            .filter { it != TelemetryMetric.SOC && it != TelemetryMetric.SPEED && it != TelemetryMetric.POWER }
            .take(CarTileLayout.MAX_TILES)
            .map { CarTileKind.Metric(it) }

        val rows: List<Row> = telemetryTab(tiles).pane.rows

        assertEquals(4, rows.size)
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
            trip = CarTripState(),
            renderer = renderer,
        )

        assertTrue(template is MessageTemplate)
        assertTrue(
            "the empty car tab should explain itself",
            (template as MessageTemplate).message.toString().isNotBlank(),
        )
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

    private fun chargingTab(charging: CarChargingState, snapshot: TelemetrySnapshot = driving) = carChargingTab(
        context = context,
        snapshot = snapshot,
        liveMetrics = supported,
        isDemoMode = true,
        connection = BleConnectionState.DemoMode,
        supportedMetrics = supported,
        charging = charging,
        renderer = renderer,
    )

    @Test
    fun theChargingTabReportsTheLiveSession() {
        val template = chargingTab(
            CarChargingState(
                isCharging = true,
                targetPercent = 80,
                secondsToTarget = 1860.0,
                deliveredKWh = 12.4,
                peakPowerKW = 61.8,
                sessionStartSocPct = 40.0,
            ),
            driving.copy(isCharging = true, chargePowerKW = 61.8),
        )

        assertEquals("Charging", template.header!!.title.toString())
        assertNotNull("the charging tab needs its dashboard", template.pane.image)
        assertEquals(
            listOf(
                "Charging" to "40% → 77%",
                "Energy delivered" to "12.4 kWh",
                "Peak power" to "61.8 kW",
            ),
            rowTexts(template),
        )
    }

    @Test
    fun anIdleChargingTabSaysSo() {
        val template = chargingTab(CarChargingState(targetPercent = 90))

        assertEquals(
            listOf(
                "Not charging" to "Plug in to start a session",
                "Energy delivered" to "0.0 kWh",
                "Peak power" to "0.0 kW",
            ),
            rowTexts(template),
        )
    }
}
