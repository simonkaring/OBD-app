package com.simonkaring.voltlink.companion

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.graphics.asAndroidBitmap
import android.graphics.Bitmap
import java.io.File
import com.simonkaring.voltlink.VoltLinkApplication
import com.simonkaring.voltlink.core.demo.DemoScenario
import org.junit.Rule
import org.junit.Test

class CompanionPreviewTest {
    @get:Rule val rule = createAndroidComposeRule<CompanionPreviewActivity>()

    @Test fun navigationAndDisconnectedState() {
        rule.onNodeWithText("Drive").assertIsDisplayed()
        rule.onNodeWithText("Disconnected · Connect the adapter in the phone app").assertIsDisplayed()
        rule.onNodeWithText("Charging", useUnmergedTree = true).performClick()
        rule.onNodeWithText("Estimated time to 80%").assertIsDisplayed()
        capture("disconnected")
        rule.onNodeWithText("Vehicle").performClick()
        rule.onNodeWithText("Profile usable capacity").assertIsDisplayed()
        val day = rule.onAllNodes(androidx.compose.ui.test.hasText("Day")).fetchSemanticsNodes().isNotEmpty()
        rule.onNodeWithText(if (day) "Day" else "Night").performClick()
        rule.onNodeWithText(if (day) "Night" else "Day").assertIsDisplayed()
    }

    @Test fun demoUsesExistingManagerAndChargingTracker() {
        val app = rule.activity.application as VoltLinkApplication
        rule.runOnIdle {
            app.vehicleData.setDemoMode(true)
            app.vehicleData.simulation.scenario = DemoScenario.DC_FAST_CHARGING
        }
        try {
            rule.onNodeWithText("Charging", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { app.chargingTracker.state.value.isCharging }
            rule.waitUntil(5_000) {
                rule.onAllNodes(androidx.compose.ui.test.hasText("Charging active")).fetchSemanticsNodes().isNotEmpty()
            }
            rule.onNodeWithText("Charging active").assertIsDisplayed()
            capture("charging")
            toggleTheme()
            capture("charging-other-theme")
            rule.onNodeWithText("Vehicle").performClick()
            capture("vehicle")
            rule.runOnIdle { app.vehicleData.simulation.scenario = DemoScenario.HIGHWAY_CRUISING }
            rule.waitUntil(30_000) { app.vehicleData.telemetry.value.speedKmH > 5 }
            rule.onNodeWithText("Drive").performClick()
            rule.waitUntil(10_000) {
                rule.onAllNodes(androidx.compose.ui.test.hasText("0 km/h")).fetchSemanticsNodes().isEmpty()
            }
            capture("drive")
            toggleTheme()
            capture("drive-other-theme")
        } finally {
            rule.runOnIdle { app.vehicleData.setDemoMode(false) }
        }
    }

    private fun toggleTheme() {
        val day = rule.onAllNodes(androidx.compose.ui.test.hasText("Day")).fetchSemanticsNodes().isNotEmpty()
        rule.onNodeWithText(if (day) "Day" else "Night").performClick()
    }

    private fun capture(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val folder = File(rule.activity.filesDir, "companion-screenshots").apply { mkdirs() }
        File(folder, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
