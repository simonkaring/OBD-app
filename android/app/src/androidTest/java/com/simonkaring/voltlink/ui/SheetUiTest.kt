package com.simonkaring.voltlink.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.data.CarTileLayout
import com.simonkaring.voltlink.ui.settings.CarTileEditorSheet
import com.simonkaring.voltlink.ui.settings.ProfileMetricStatusSheet
import com.simonkaring.voltlink.ui.theme.VoltLinkTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SheetUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun metricStatusReportsLiveNoDataAndNotConnected() {
        rule.setContent {
            VoltLinkTheme {
                ProfileMetricStatusSheet(
                    profileName = "Test vehicle",
                    supportedMetrics = setOf(
                        TelemetryMetric.SOC,
                        TelemetryMetric.SPEED,
                        TelemetryMetric.POWER,
                    ),
                    liveMetrics = setOf(TelemetryMetric.SOC),
                    isConnected = true,
                    isDemoMode = false,
                    isCommunityObdbProfile = false,
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText("Profile metric status").assertIsDisplayed()
        rule.onNodeWithText("Test vehicle — 3 metrics").assertIsDisplayed()
        rule.onNodeWithText("Live").assertIsDisplayed()
        // Power and speed both report no data yet.
        rule.onAllNodesWithText("No data").onFirst().assertIsDisplayed()
    }

    @Test
    fun carLayoutEditorAddsRowsUpToTheTemplateLimit() {
        val layout = CarTileLayout(listOf(CarTileKind.Metric(TelemetryMetric.SOC)))
        var changed: CarTileLayout? = null
        rule.setContent {
            VoltLinkTheme {
                CarTileEditorSheet(
                    layout = layout,
                    supportedMetrics = setOf(TelemetryMetric.SOC, TelemetryMetric.BATTERY_TEMP),
                    onChange = { changed = it },
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText("Android Auto layout").assertIsDisplayed()
        rule.onNodeWithText("Diagnostics").performClick()

        assertEquals(
            listOf(CarTileKind.Metric(TelemetryMetric.SOC), CarTileKind.Health),
            changed?.tiles,
        )
    }

    @Test
    fun homeScreenSectionsAreReachableFromTheShell() {
        var dismissed = false
        rule.setContent {
            VoltLinkTheme {
                ProfileMetricStatusSheet(
                    profileName = "Demo",
                    supportedMetrics = setOf(TelemetryMetric.SPEED),
                    liveMetrics = emptySet(),
                    isConnected = false,
                    isDemoMode = false,
                    isCommunityObdbProfile = false,
                    onDismiss = { dismissed = true },
                )
            }
        }

        rule.onNodeWithText("Not connected").assertIsDisplayed()
        rule.onNodeWithText("Done").performClick()
        assertTrue(dismissed)
    }
}
