package com.simonkaring.voltlink.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.data.DashboardLayout
import com.simonkaring.voltlink.ui.dashboard.DashboardCustomizationSheet
import com.simonkaring.voltlink.ui.theme.VoltLinkTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DashboardCustomizationSheetTest {
    @get:Rule
    val rule = createComposeRule()

    private fun showSheet(
        layout: DashboardLayout = DashboardLayout.default,
        onDismiss: () -> Unit = {},
        onChange: (DashboardLayout) -> Unit = {},
    ) {
        rule.setContent {
            VoltLinkTheme {
                DashboardCustomizationSheet(
                    layout = layout,
                    supportedMetrics = setOf(
                        TelemetryMetric.SOC,
                        TelemetryMetric.SPEED,
                        TelemetryMetric.POWER,
                        TelemetryMetric.BATTERY_TEMP,
                    ),
                    liveMetrics = setOf(TelemetryMetric.SOC, TelemetryMetric.SPEED),
                    profileName = "Test vehicle",
                    isConnected = true,
                    isDemoMode = false,
                    onChange = onChange,
                    onDismiss = onDismiss,
                )
            }
        }
    }

    @Test
    fun showsEveryWidgetWithItsLiveStatus() {
        showSheet()

        rule.onNodeWithText("Customize dashboard").assertIsDisplayed()
        rule.onNodeWithText("Test vehicle").assertIsDisplayed()
        rule.onNodeWithText("Speed").assertIsDisplayed()
        // Several widgets are live at once; the first status label is enough to prove the copy.
        rule.onAllNodesWithText("Live").onFirst().assertIsDisplayed()
    }

    @Test
    fun doneDismissesAndResetRestoresTheDefaultLayout() {
        var dismissed = false
        var changed: DashboardLayout? = null
        showSheet(
            layout = DashboardLayout(listOf(DashboardLayout.default.widgets.first())),
            onDismiss = { dismissed = true },
            onChange = { changed = it },
        )

        rule.onNodeWithText("Reset").performClick()
        assertEquals(DashboardLayout.default, changed)

        rule.onNodeWithText("Done").performClick()
        assertTrue(dismissed)
    }

    @Test
    fun addingAMetricAppendsAWidgetTheProfileSupports() {
        var changed: DashboardLayout? = null
        showSheet(onChange = { changed = it })

        // The add gallery sits below the configured widgets inside the scrolling list.
        rule.onNode(hasScrollAction()).performScrollToNode(hasText("HV Battery Temp"))
        rule.onNodeWithText("HV Battery Temp").performClick()

        assertEquals(
            DashboardLayout.default.widgets.size + 1,
            changed?.widgets?.size,
        )
    }
}
