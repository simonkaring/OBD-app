package com.simonkaring.voltlink

import android.Manifest
import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import com.simonkaring.voltlink.core.demo.DemoScenario
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Records the app's screens as PNGs for visual review of design changes: dashboard, trip
 * log, charging, diagnostics, an expanded DTC entry, the demo control sheet, settings and the
 * mirrored HUD.
 *
 * Each capture is copied out of the app's private storage into
 * `/sdcard/Download/voltlink-screenshots/`, which `adb pull` can read and which survives the
 * uninstall that `connectedDebugAndroidTest` performs afterwards. Collect them with
 * `./gradlew recordScreenshots`.
 *
 * These are recordings, not golden-image comparisons: pixel baselines depend on the device's
 * density, fonts and API level, so the tests assert that each screen actually rendered (a
 * non-blank, multi-colour frame of the expected size) instead of diffing against a checked-in
 * PNG. Run the class on a second device or API level to compare renders by eye.
 */
@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.POST_NOTIFICATIONS,
    )

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun dashboardScreenshot() {
        awaitDemoDashboard()
        capture("dashboard")
    }

    @Test
    fun tripsScreenshot() {
        awaitDemoDashboard()

        rule.onNodeWithText("Log").performClick().assertIsSelected()
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("Start Trip").fetchSemanticsNodes().isNotEmpty() ||
                rule.onAllNodesWithText("Stop Trip").fetchSemanticsNodes().isNotEmpty()
        }
        capture("trips")
    }

    @Test
    fun chargingScreenshot() {
        awaitDemoDashboard()

        rule.onNodeWithText("Charging").performClick().assertIsSelected()
        capture("charging")
    }

    @Test
    fun diagnosticsScreenshot() {
        awaitDemoDashboard()

        // Scan rather than capture the untouched screen: the scanner state outlives an activity
        // in the instrumentation process, so "scan not performed" would depend on test order.
        // Clear the demo fault first so this capture stays a no-codes screen either way.
        (rule.activity.application as VoltLinkApplication).vehicleData.simulation
            .clearInjectedFault()
        rule.onNodeWithText("Diagnostics").performClick().assertIsSelected()
        rule.onNodeWithText("Scan DTCs").performClick()
        rule.waitUntil(timeoutMillis = 20_000) {
            rule.onAllNodesWithText("No fault codes reported by the ECUs that answered.")
                .fetchSemanticsNodes().isNotEmpty()
        }
        capture("diagnostics")
    }

    @Test
    fun dtcDetailScreenshot() {
        awaitDemoDashboard()

        // The simulated ECUs only report P0A80 while the fault scenario is active, so inject it
        // before the scan and restore the default driving cycle afterwards.
        val app = rule.activity.application as VoltLinkApplication
        app.vehicleData.simulation.scenario = DemoScenario.FAULT_INJECTION
        try {
            rule.onNodeWithText("Diagnostics").performClick().assertIsSelected()
            rule.onNodeWithText("Scan DTCs").performClick()

            // The card only shows the curated title once the scan has finished.
            rule.waitUntil(timeoutMillis = 20_000) {
                rule.onAllNodesWithText("Replace Hybrid/EV Battery Pack").fetchSemanticsNodes().isNotEmpty()
            }
            rule.onNodeWithText("Replace Hybrid/EV Battery Pack").performClick()

            // Expanding the card reveals the repair guidance the screenshot is meant to show.
            rule.waitUntil(timeoutMillis = 15_000) {
                rule.onAllNodesWithText("Possible fixes").fetchSemanticsNodes().isNotEmpty()
            }
            // Bring the repair guidance into view; it sits below the fold on a phone screen.
            // The expansion animates in, so let it finish before the list can scroll.
            rule.waitForIdle()
            Thread.sleep(SETTLE_MILLIS)
            rule.onNode(hasScrollAction()).performScrollToNode(
                hasText("Perform battery module balancing or pack replacement", substring = true),
            )
            capture("dtc-detail")
        } finally {
            // Also leaves the fault scenario, so later captures start from a clean demo state.
            app.vehicleData.simulation.clearInjectedFault()
        }
    }

    @Test
    fun demoControlsScreenshot() {
        awaitDemoDashboard()

        // The dashboard header's Controls button opens the demo/simulation sheet.
        rule.onNodeWithText("Controls").performClick()
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("Diagnostic Fault Injection").fetchSemanticsNodes().isNotEmpty()
        }
        try {
            // The sheet opens half-height, which cuts off the sliders; drag it open so the whole
            // control set is in the frame. The drag starts on the title, away from the sliders.
            repeat(MAX_SHEET_DRAGS) {
                if (isDisplayed("Live Adapter")) return@repeat
                rule.onNodeWithText("Demo / Simulation").performTouchInput {
                    swipe(
                        start = Offset(centerX, centerY + 400f),
                        end = Offset(centerX, centerY - 400f),
                        durationMillis = 400,
                    )
                }
                rule.waitForIdle()
            }
            capture("demo-controls")
        } finally {
            // Dismiss so the sheet's scrim does not sit over the captures that follow.
            rule.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
            rule.waitUntil(timeoutMillis = 10_000) { !isDisplayed("Demo / Simulation") }
        }
    }

    @Test
    fun hudScreenshot() {
        awaitDemoDashboard()

        rule.onNodeWithText("HUD").performClick()
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("DEMO").fetchSemanticsNodes().isNotEmpty()
        }
        capture("hud")
    }

    @Test
    fun settingsScreenshot() {
        awaitDemoDashboard()

        rule.onNodeWithText("Settings").performClick().assertIsSelected()
        // The demo toggle sits in the first card, so this proves the settings content composed.
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("Demo / Simulation mode").fetchSemanticsNodes().isNotEmpty()
        }
        capture("settings")
    }

    /** The shell starts in demo mode; the status chip proves simulated telemetry is flowing. */
    private fun awaitDemoDashboard() {
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("Demo mode").fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** Whether a node with this text exists and is fully on screen. */
    private fun isDisplayed(text: String): Boolean =
        runCatching { rule.onNodeWithText(text).assertIsDisplayed() }.isSuccess

    private fun capture(name: String) {
        rule.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdleSync()
        // Let the frame with the settled composition reach the screen before grabbing pixels.
        Thread.sleep(SETTLE_MILLIS)

        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        assertRendered(name, bitmap)
        publish(name, bitmap)
    }

    /**
     * Fails when a screen came up empty, white or crashed: a rendered VoltLink screen samples
     * its dark background, cyan accents and text over a wide range of colours.
     */
    private fun assertRendered(name: String, bitmap: Bitmap) {
        assertTrue("$name screenshot has no pixels", bitmap.width > 0 && bitmap.height > 0)
        assertTrue("$name screenshot is smaller than a phone screen", bitmap.width >= 480)

        val sampledColors = mutableSetOf<Int>()
        var x = 0
        while (x < bitmap.width) {
            var y = 0
            while (y < bitmap.height) {
                sampledColors += bitmap.getPixel(x, y)
                y += SAMPLE_STEP
            }
            x += SAMPLE_STEP
        }
        assertTrue(
            "$name screenshot looks blank (${sampledColors.size} sampled colours)",
            sampledColors.size > 8,
        )
    }

    /**
     * Writes the PNG into the app's external files directory, then copies it to the shared
     * `Download/voltlink-screenshots` folder through the UiAutomation shell. Shell owns the
     * destination, so the image outlives the app uninstall and no storage permission is needed.
     */
    private fun publish(name: String, bitmap: Bitmap) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val local = requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)) {
            "External files directory is unavailable, cannot store the $name screenshot"
        }.resolve("$name.png")

        FileOutputStream(local).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue("$name screenshot was not written", local.length() > 0)

        shell("mkdir -p $REMOTE_DIRECTORY")
        shell("cp ${local.absolutePath} $REMOTE_DIRECTORY/$name.png")
        shell("chmod 644 $REMOTE_DIRECTORY/$name.png")

        val listing = shell("ls -l $REMOTE_DIRECTORY/$name.png")
        assertTrue("$name screenshot was not published: $listing", listing.contains("$name.png"))
    }

    /** Runs a command as the instrumentation shell and returns its output. */
    private fun shell(command: String): String {
        val descriptor: ParcelFileDescriptor =
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
    }

    private companion object {
        const val REMOTE_DIRECTORY = "/sdcard/Download/voltlink-screenshots"
        const val MAX_SHEET_DRAGS = 3
        const val SETTLE_MILLIS = 750L
        const val SAMPLE_STEP = 32
    }
}
