package com.simonkaring.voltlink

import android.Manifest
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Demo-mode smoke test: the shell boots into simulated telemetry without an adapter. */
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
