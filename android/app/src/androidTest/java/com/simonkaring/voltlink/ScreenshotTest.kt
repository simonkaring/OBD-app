package com.simonkaring.voltlink

import android.Manifest
import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Records the app's screens as PNGs for visual review of design changes: dashboard, trip
 * log, charging, diagnostics, settings and the mirrored HUD.
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

        rule.onNodeWithText("Diagnostics").performClick().assertIsSelected()
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("System health").fetchSemanticsNodes().isNotEmpty()
        }
        capture("diagnostics")
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
        const val SETTLE_MILLIS = 750L
        const val SAMPLE_STEP = 32
    }
}
