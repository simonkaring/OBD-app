package com.simonkaring.voltlink.companion

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.compose.ui.graphics.toArgb
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.CarColor
import androidx.core.graphics.drawable.IconCompat
import androidx.car.app.model.TabTemplate
import androidx.car.app.annotations.ExperimentalCarApi
import androidx.test.core.app.ApplicationProvider
import com.simonkaring.voltlink.VoltLinkApplication
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.ui.theme.Theme
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class CompanionCarTemplateTest {
    private val app = ApplicationProvider.getApplicationContext<VoltLinkApplication>()
    private val callback = object : TabTemplate.TabCallback {}

    @Test fun vehicleListsEveryMetricTheProfileAdvertisesAndKeepsMissingOnes() {
        val supported = setOf(TelemetryMetric.SOC, TelemetryMetric.PACK_VOLTAGE,
            TelemetryMetric.PACK_CURRENT, TelemetryMetric.POWER, TelemetryMetric.SOH)
        val state = readState(app).copy(
            supportedMetrics = supported,
            metrics = mapOf(TelemetryMetric.SOC to 72.0, TelemetryMetric.PACK_VOLTAGE to 398.2),
        )
        val template = companionCarTemplate(app, state, "vehicle", callback)
        assertEquals(3, template.tabs.size)
        assertEquals("vehicle", template.activeTabContentId)
        fun rows(state: CompanionState) = (companionCarTemplate(app, state, "vehicle", callback)
            .tabContents.template as ListTemplate).singleList!!.items.map { it as Row }
        fun Row.value() = texts.single().toString()
        val first = rows(state)
        // Battery first (with the connection status), then the remaining metrics in enum order,
        // then the profile capacity, which is a specification rather than a measured signal.
        assertEquals(listOf(app.getString(R.string.companion_soc), "Power", "State of Health",
            "Pack Voltage", "Pack Current", app.getString(R.string.companion_capacity)),
            first.map { it.title.toString() })
        assertTrue(first[0].value().startsWith("72 % · "))
        assertEquals("—", first[1].value())
        assertEquals("398.2 V", first[3].value())
        assertEquals(number(state.capacityKWh, 1, "kWh"), first.last().value())
        assertTrue(first.all { it.image == null && it.onClickDelegate == null })
        // A reading that never arrives keeps its row; only the value text changes.
        val next = rows(state.copy(metrics = emptyMap()))
        assertEquals(first.map { it.title.toString() }, next.map { it.title.toString() })
        assertEquals("—", next[3].value())
        // Metrics the selected profile does not advertise are never listed.
        assertEquals(listOf(app.getString(R.string.companion_soc), app.getString(R.string.companion_capacity)),
            rows(state.copy(supportedMetrics = setOf(TelemetryMetric.SOC))).map { it.title.toString() })
    }

    @Test fun chargingUsesSixStableTilesLeadingWithBatteryAndRange() {
        fun items(state: CompanionState, dark: Boolean = false) =
            ((companionCarTemplate(app, state, "charging", callback, darkMode = dark)
                .tabContents.template as GridTemplate).singleList!!.items).map { it as GridItem }
        val state = readState(app).copy(charging = CompanionCharging.ACTIVE,
            metrics = mapOf(TelemetryMetric.SOC to 72.0), rangeKm = 312.0, rangeEstimated = false,
            chargePowerKW = 43.2, chargePowerEstimated = true,
            secondsTo80 = 601.0, chargingSeconds = 3661, energyAddedKWh = 12.34, costDKK = 24.68)
        val first = items(state)
        assertEquals(6, first.size)
        // The same battery and range tiles the Drive grid leads with, then the session tiles.
        assertEquals("72 % · Charge", first[0].text.toString())
        assertEquals("312 km", first[1].text.toString())
        assertEquals("≈ 43.2 kW", first[2].text.toString())
        assertEquals("≈ 11 min", first[3].text.toString())
        assertEquals("1:01", first[4].text.toString())
        assertEquals("12.34 kWh · ≈ 24.68 DKK", first[5].text.toString())
        assertEquals("Elapsed", first[4].title.toString())
        assertTrue(first.all { it.onClickDelegate == null && it.imageType == GridItem.IMAGE_TYPE_LARGE })
        // Battery reuses Drive's discrete level icon; charge power keeps the dial image experiment.
        assertEquals(R.drawable.ic_companion_battery_5, batteryLevelIcon(72.0))
        assertTrue(first[0].image!!.icon!!.type == IconCompat.TYPE_RESOURCE && first[0].image!!.tint == CarColor.DEFAULT)
        assertTrue(first[2].image!!.icon!!.type == IconCompat.TYPE_RESOURCE && first[2].image!!.tint == null)
        assertTrue(listOf(1, 3, 4, 5).all { first[it].image!!.tint == CarColor.DEFAULT })
        val next = items(state.copy(metrics = mapOf(TelemetryMetric.SOC to 92.0), chargePowerKW = 65.0))
        assertEquals(first.map { it.title.toString() }, next.map { it.title.toString() })
        // A fresh SOC level redraws the battery icon; the power dial also changes with its value and theme.
        assertNotEquals(first[0].image, next[0].image)
        assertNotEquals(first[2].image, next[2].image)
        assertNotEquals(first[2].image, items(state, true)[2].image)
        for ((status, label) in listOf(CompanionCharging.DISCONNECTED to "Offline",
            CompanionCharging.UNAVAILABLE to "Unknown", CompanionCharging.INACTIVE to "Not charging",
            CompanionCharging.COMPLETE to "Stopped · Target reached")) {
            val missing = items(state.copy(charging = status, metrics = emptyMap(), rangeKm = null,
                chargePowerKW = null, secondsTo80 = null, chargingSeconds = null,
                energyAddedKWh = null, costDKK = null))
            assertEquals(first.map { it.title.toString() }, missing.map { it.title.toString() })
            assertEquals("— · $label", missing[0].text.toString())
            // Range, power, ETA and elapsed each show one placeholder; energy keeps two.
            for (index in 1..4) assertEquals("—", missing[index].text.toString())
            assertEquals("— · —", missing[5].text.toString())
        }
    }

    @Test fun chargingImagesKeepUnknownDistinctAndFullSocOnlyAt100Percent() {
        for (invalid in listOf(null, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertEquals(ChargingImageFrame.UNKNOWN, ChargingImageExperiment.socFrame(invalid))
            // No live power means "not charging yet", so the dial keeps the bolt instead of a question mark.
            assertEquals(ChargingImageFrame.IDLE, ChargingImageExperiment.powerFrame(invalid))
        }
        // Zero is a real reading with nothing flowing: grey idle, neither green nor unknown.
        assertEquals(ChargingImageFrame.IDLE, ChargingImageExperiment.powerFrame(0.0))
        assertEquals(ChargingImageFrame.UNKNOWN, ChargingImageExperiment.socFrame(100.01))
        assertEquals(ChargingImageFrame.LEVEL_0, ChargingImageExperiment.socFrame(0.0))
        assertEquals(ChargingImageFrame.LEVEL_9, ChargingImageExperiment.socFrame(99.99))
        assertEquals(ChargingImageFrame.LEVEL_10, ChargingImageExperiment.socFrame(100.0))
        for (step in 0..10) {
            assertEquals(ChargingImageFrame.entries[step + 2], ChargingImageExperiment.socFrame(step * 10.0))
            if (step > 0) assertEquals(ChargingImageFrame.entries[step + 2], ChargingImageExperiment.powerFrame(step * 20.0))
        }
        assertEquals(ChargingImageFrame.LEVEL_0, ChargingImageExperiment.powerFrame(19.99))
        assertEquals(ChargingImageFrame.LEVEL_10, ChargingImageExperiment.powerFrame(Double.MAX_VALUE))
        val image = ChargingImageExperiment.icon(app, ChargingImageExperiment.powerFrame(43.2), true)
        assertSame(image, ChargingImageExperiment.icon(app, ChargingImageExperiment.powerFrame(59.9), true))
        assertNotEquals(image, ChargingImageExperiment.icon(app, ChargingImageFrame.LEVEL_3, true))
        assertNotEquals(image, ChargingImageExperiment.icon(app, ChargingImageFrame.LEVEL_2, false))
        assertEquals(26, ChargingImageFrame.entries.flatMap { listOf(it.lightImage, it.darkImage) }.toSet().size)
        checkFrames("charging", listOf(false, true).flatMap { dark -> ChargingImageFrame.entries.map { frame ->
            Triple("${frame.name.lowercase()}_${if (dark) "dark" else "light"}",
                ChargingImageExperiment.render(app, frame, dark), if (dark) frame.darkImage else frame.lightImage)
        } })
        val bitmap = ChargingImageExperiment.render(app, ChargingImageFrame.LEVEL_10, true)
        // The charge bolt sits in the hub, so this dial cannot be mistaken for the speed dial.
        assertTrue(paintedHub(bitmap) > 0)
        assertEquals(255, Color.alpha(bitmap.getPixel(16, 104)))
        // The dial reads green while charging, matching the phone's charging colour.
        val green = Theme.regenGreen.toArgb()
        assertTrue("Charging dial is green",
            (0 until bitmap.height).any { y -> (0 until bitmap.width).any { x -> bitmap.getPixel(x, y) == green } })
        // At zero nothing is flowing, so the bolt and arc stay neutral grey.
        val idle = ChargingImageExperiment.render(app, ChargingImageFrame.IDLE, true)
        assertTrue("Idle dial keeps the bolt", paintedHub(idle) > 0)
        assertFalse("Idle dial is not green",
            (0 until idle.height).any { y -> (0 until idle.width).any { x -> idle.getPixel(x, y) == green } })
    }

    @Test fun driveUsesStableNativeGridWithLiveValuesInSecondaryText() {
        val state = readState(app)
        fun grid(state: CompanionState) = companionCarTemplate(app, state, "drive", callback)
            .tabContents.template as GridTemplate
        val first = grid(state.copy(metrics = emptyMap()))
        val updated = grid(state.copy(metrics = mapOf(TelemetryMetric.SOC to 72.0, TelemetryMetric.POWER to -18.5)))
        val items = first.singleList!!.items.map { it as GridItem }
        val refreshed = updated.singleList!!.items.map { it as GridItem }
        assertEquals(6, items.size)
        assertEquals(items.map { it.title.toString() }, refreshed.map { it.title.toString() })
        assertTrue(refreshed[0].text.toString().startsWith("72 %"))
        assertEquals("Range", items[1].title.toString())
        assertEquals("-18.5 kW · Energy in", refreshed[3].text.toString())
        assertEquals("— · Unknown", items[3].text.toString())
        assertTrue(items.all { it.image != null && it.imageType == GridItem.IMAGE_TYPE_LARGE })
        assertTrue(items.filterIndexed { index, _ -> index !in 2..3 }.all { it.image!!.tint == CarColor.DEFAULT })
        for (index in 2..3) {
            assertEquals(IconCompat.TYPE_RESOURCE, items[index].image!!.icon!!.type)
            assertNull(items[index].image!!.tint)
        }
        assertTrue(items.all { it.onClickDelegate == null })
    }

    @Test fun powerImageUsesCoarseBucketsAndNeverCallsChargingRegen() {
        val state = readState(app).copy(charging = CompanionCharging.INACTIVE,
            metrics = mapOf(TelemetryMetric.SPEED to 40.0))
        fun frame(power: Double) = PowerImageExperiment.frame(state.copy(metrics = state.metrics + (TelemetryMetric.POWER to power)))
        assertEquals(PowerImageFrame.UNKNOWN, PowerImageExperiment.frame(state))
        assertEquals(PowerImageFrame.UNKNOWN, frame(Double.NaN))
        assertEquals(PowerImageFrame.IDLE, frame(0.0))
        assertEquals(PowerImageFrame.DRAW_LOW, frame(24.99))
        assertEquals(PowerImageFrame.DRAW_MID, frame(25.0))
        assertEquals(PowerImageFrame.DRAW_HIGH, frame(75.0))
        assertEquals(PowerImageFrame.REGEN_LOW, frame(-9.99))
        assertEquals(PowerImageFrame.REGEN_MID, frame(-10.0))
        assertEquals(PowerImageFrame.REGEN_HIGH, frame(-30.0))
        assertEquals(PowerImageFrame.CHARGING, PowerImageExperiment.frame(state.copy(charging = CompanionCharging.ACTIVE,
            metrics = state.metrics + (TelemetryMetric.POWER to -30.0))))
        assertEquals(PowerImageFrame.ENERGY_IN, PowerImageExperiment.frame(state.copy(metrics = mapOf(TelemetryMetric.POWER to -30.0))))
    }

    @Test fun powerImagesAreCachedWithinEachBucketAndRenderedForBothThemes() {
        val state = readState(app).copy(charging = CompanionCharging.INACTIVE,
            metrics = mapOf(TelemetryMetric.POWER to 30.0))
        val image = PowerImageExperiment.icon(app, state, true)
        assertSame(image, PowerImageExperiment.icon(app, state.copy(metrics = mapOf(TelemetryMetric.POWER to 40.0)), true))
        assertNotSame(image, PowerImageExperiment.icon(app, state, false))
        assertNotEquals(image, PowerImageExperiment.icon(app, state, false))
        assertEquals(20, PowerImageFrame.entries.flatMap { listOf(it.lightImage, it.darkImage) }.toSet().size)
        checkFrames("power", listOf(false, true).flatMap { dark -> PowerImageFrame.entries.map { frame ->
            Triple("${frame.name.lowercase()}_${if (dark) "dark" else "light"}",
                PowerImageExperiment.render(app, frame, dark), if (dark) frame.darkImage else frame.lightImage)
        } })
        for (frame in listOf(PowerImageFrame.IDLE, PowerImageFrame.DRAW_HIGH, PowerImageFrame.REGEN_HIGH)) {
            val bitmap = PowerImageExperiment.render(app, frame, true)
            // Still needle-free, but the hub now carries the direction glyph that identifies power.
            assertTrue("Hub glyph", paintedHub(bitmap) > 0)
            assertEquals("Thicker arc", 255, Color.alpha(bitmap.getPixel(16, 104)))
        }
    }

    @Test fun speedImagesUseBoundedStepsWithDistinctUnknownAndCachedThemeResources() {
        listOf(null, Double.NaN, Double.POSITIVE_INFINITY, -1.0).forEach {
            assertEquals(SpeedImageFrame.UNKNOWN, SpeedImageExperiment.frame(it))
        }
        assertEquals(SpeedImageFrame.STOPPED, SpeedImageExperiment.frame(0.0))
        assertEquals(SpeedImageFrame.SPEED_20, SpeedImageExperiment.frame(0.01))
        assertEquals(SpeedImageFrame.SPEED_20, SpeedImageExperiment.frame(20.0))
        assertEquals(SpeedImageFrame.SPEED_40, SpeedImageExperiment.frame(20.01))
        for (step in 1..8) assertEquals(SpeedImageFrame.entries[step + 1], SpeedImageExperiment.frame(step * 20.0))
        assertEquals(SpeedImageFrame.SPEED_160, SpeedImageExperiment.frame(Double.MAX_VALUE))
        val image = SpeedImageExperiment.icon(app, 25.0, true)
        assertSame(image, SpeedImageExperiment.icon(app, 40.0, true))
        assertNotEquals(image, SpeedImageExperiment.icon(app, 41.0, true))
        assertNotEquals(image, SpeedImageExperiment.icon(app, 25.0, false))
        assertEquals(20, SpeedImageFrame.entries.flatMap { listOf(it.lightImage, it.darkImage) }.toSet().size)
        checkFrames("speed", listOf(false, true).flatMap { dark -> SpeedImageFrame.entries.map { frame ->
            Triple("${frame.name.lowercase()}_${if (dark) "dark" else "light"}",
                SpeedImageExperiment.render(app, frame, dark), if (dark) frame.darkImage else frame.lightImage)
        } })
        // The gauge glyph in the hub distinguishes the speed dial from the power and charge dials.
        assertTrue(paintedHub(SpeedImageExperiment.render(app, SpeedImageFrame.SPEED_160, true)) > 0)
    }

    /** Pixels painted inside a dial hub, where the quantity glyph sits. */
    private fun paintedHub(bitmap: Bitmap) =
        (86..122).sumOf { y -> (78..114).count { x -> bitmap.getPixel(x, y) != 0 } }

    private fun checkFrames(kind: String, frames: List<Triple<String, Bitmap, Int>>) {
        val hashes = mutableSetOf<Int>()
        val drift = mutableListOf<String>()
        val sheet = Bitmap.createBitmap(960, ((frames.size + 4) / 5) * 216, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 13f; textAlign = Paint.Align.CENTER }
        for ((index, frame) in frames.withIndex()) {
            val (name, bitmap, resource) = frame
            val dark = name.endsWith("dark")
            val packaged = BitmapFactory.decodeResource(app.resources, resource)
            if (!bitmap.sameAs(packaged)) drift += name
            val output = File(app.filesDir, "$kind-image-frames").apply { mkdirs() }
            File(output, "${kind}_image_$name.png").outputStream().use {
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
            assertEquals(192, bitmap.width)
            assertEquals(192, bitmap.height)
            assertEquals(0, bitmap.getPixel(0, 0))
            val pixels = IntArray(192 * 192)
            bitmap.getPixels(pixels, 0, 192, 0, 0, 192, 192)
            assertTrue(pixels.any { it != 0 })
            hashes += pixels.contentHashCode()
            val x = index % 5 * 192f
            val y = index / 5 * 216f
            paint.color = if (dark) Color.rgb(32, 34, 37) else Color.rgb(242, 245, 247)
            canvas.drawRect(x, y, x + 192, y + 216, paint)
            canvas.drawBitmap(bitmap, x, y, null)
            paint.color = if (dark) Color.WHITE else Color.BLACK
            canvas.drawText(name.removeSuffix(if (dark) "_dark" else "_light"), x + 96, y + 207, paint)
        }
        assertEquals(frames.size, hashes.size)
        File(app.filesDir, "$kind-image-experiment.png").outputStream().use {
            assertTrue(sheet.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
        assertTrue("Packaged $kind frame drift: $drift", drift.isEmpty())
    }

    @Test fun batteryLevelsCoverEmptyToFullWithoutTreatingUnknownAsEmpty() {
        val levels = listOf(0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 100.0).map(::batteryLevelIcon)
        assertEquals(8, levels.toSet().size)
        assertEquals(R.drawable.ic_companion_battery, levels.first())
        assertEquals(R.drawable.ic_companion_battery_5, batteryLevelIcon(78.0))
        assertEquals(R.drawable.ic_companion_battery_6, batteryLevelIcon(99.9))
        assertEquals(R.drawable.ic_companion_battery_full, levels.last())
        listOf(null, Double.NaN, Double.POSITIVE_INFINITY, -1.0, 101.0).forEach {
            assertEquals(R.drawable.ic_companion_battery_unknown, batteryLevelIcon(it))
        }
    }

    @Test fun powerIconsDistinguishDrawRegenChargingIdleAndUnknown() {
        val state = readState(app).copy(charging = CompanionCharging.INACTIVE,
            metrics = mapOf(TelemetryMetric.POWER to -20.0, TelemetryMetric.SPEED to 40.0))
        assertEquals(R.drawable.ic_companion_regen to R.string.companion_grid_regen, powerIndicator(state))
        assertEquals(R.drawable.ic_car_charging to R.string.companion_grid_charging,
            powerIndicator(state.copy(charging = CompanionCharging.ACTIVE)))
        assertEquals(R.drawable.ic_companion_regen to R.string.companion_grid_energy_in,
            powerIndicator(state.copy(metrics = mapOf(TelemetryMetric.POWER to -20.0))))
        assertEquals(R.drawable.ic_companion_draw to R.string.companion_grid_draw,
            powerIndicator(state.copy(metrics = mapOf(TelemetryMetric.POWER to 20.0))))
        assertEquals(R.drawable.ic_companion_idle to R.string.companion_grid_idle,
            powerIndicator(state.copy(metrics = mapOf(TelemetryMetric.POWER to 0.0))))
        assertEquals(R.drawable.ic_companion_unknown to R.string.companion_grid_unknown,
            powerIndicator(state.copy(metrics = emptyMap())))
    }

    @Test fun changingSignalIconsPreservesGridRefreshStructureAndCompactReadouts() {
        val state = readState(app).copy(charging = CompanionCharging.INACTIVE,
            metrics = mapOf(TelemetryMetric.SOC to 20.0, TelemetryMetric.POWER to 30.0, TelemetryMetric.SPEED to 40.0),
            tripConsumption = 173.1, tripDistanceKm = 0.3, tripSeconds = 71)
        fun items(state: CompanionState) = (companionCarTemplate(app, state, "drive", callback)
            .tabContents.template as GridTemplate).singleList!!.items.map { it as GridItem }
        val first = items(state)
        val next = items(state.copy(metrics = state.metrics + (TelemetryMetric.SOC to 78.0) +
            (TelemetryMetric.POWER to -30.0) + (TelemetryMetric.SPEED to 80.0)))
        assertEquals(first.map { it.title.toString() }, next.map { it.title.toString() })
        assertNotEquals(first[0].image, next[0].image)
        assertNotEquals(first[2].image, next[2].image)
        assertEquals("40 km/h", first[2].text.toString())
        assertEquals("80 km/h", next[2].text.toString())
        assertNotEquals(first[3].image, next[3].image)
        assertEquals(app.getString(R.string.companion_grid_consumption), first[4].title.toString())
        assertEquals("173.1", first[4].text.toString())
        assertEquals("0.3 km · 0:01", first[5].text.toString())
        assertEquals("—", gridTripTime(null))
        assertEquals("1:01", gridTripTime(3661))
        assertEquals("0:00", gridTripTime(-1))
    }

    @androidx.annotation.OptIn(ExperimentalCarApi::class)
    @Test fun largeTilesAreRequestedOnlyWhenHostSupportsApi8() {
        val state = readState(app)
        for (tab in listOf("drive", "charging")) {
            fun grid(api: Int) = companionCarTemplate(app, state, tab, callback, api)
                .tabContents.template as GridTemplate
            assertEquals(GridTemplate.ITEM_SIZE_SMALL, grid(7).itemSize)
            assertEquals(GridTemplate.ITEM_SIZE_LARGE, grid(8).itemSize)
            assertEquals(GridTemplate.ITEM_SIZE_LARGE, grid(9).itemSize)
            assertEquals(grid(7).singleList!!.items.size, grid(8).singleList!!.items.size)
        }
    }

    @Test fun debugBuildIsDiscoverableOnlyAsIot() {
        val intent = Intent("androidx.car.app.CarAppService").setPackage(app.packageName)
        val services = app.packageManager.queryIntentServices(intent, PackageManager.GET_RESOLVED_FILTER)
        assertEquals(1, services.size)
        assertTrue(services.single().filter.hasCategory("androidx.car.app.category.IOT"))
        assertFalse(services.single().filter.hasCategory("androidx.car.app.category.POI"))
        assertEquals(CompanionCarService::class.java.name, services.single().serviceInfo.name)
    }
}
