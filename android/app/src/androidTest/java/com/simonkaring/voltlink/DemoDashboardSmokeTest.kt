package com.simonkaring.voltlink

import android.Manifest
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import com.simonkaring.voltlink.ui.settings.DEMO_MODE_TOGGLE_TAG
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Demo-mode smoke test: the shell boots disconnected, the Settings switch starts the
 * simulation, and every tab renders against simulated telemetry without an adapter.
 */
@RunWith(AndroidJUnit4::class)
class DemoDashboardSmokeTest {
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.POST_NOTIFICATIONS,
    )

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun demoDashboardAndTabsRender() {
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("Telemetry").fetchSemanticsNodes().isNotEmpty()
        }

        // Demo mode is never persisted, so the test has to switch it on like a user would.
        rule.onNodeWithText("Settings").performClick()
        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithTag(DEMO_MODE_TOGGLE_TAG).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNodeWithTag(DEMO_MODE_TOGGLE_TAG).performClick()
        rule.onNodeWithText("Telemetry").performClick()

        rule.waitUntil(timeoutMillis = 15_000) {
            rule.onAllNodesWithText("Demo mode").fetchSemanticsNodes().isNotEmpty()
        }

        rule.onNodeWithText("Demo mode").assertIsDisplayed()
        rule.onNodeWithText("Layout").assertIsDisplayed()
        rule.onNodeWithText("Telemetry").assertIsDisplayed()
        rule.onNodeWithText("Charging").assertIsDisplayed()
        rule.onNodeWithText("Diagnostics").assertIsDisplayed()
        rule.onNodeWithText("Settings").assertIsDisplayed()
    }
}
