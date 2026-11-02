package com.simonkaring.voltlink.data

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DashboardLayoutTest {
    @Test
    fun `default layout drops metrics the profile cannot report`() {
        val adapted = DashboardLayout.default.adapted(setOf(TelemetryMetric.SOC, TelemetryMetric.SPEED))

        assertEquals(
            listOf(
                DashboardWidgetKind.Metric(TelemetryMetric.SPEED),
                DashboardWidgetKind.Metric(TelemetryMetric.SOC),
                DashboardWidgetKind.Chart(listOf(TelemetryMetric.SPEED)),
            ),
            adapted.widgets.map { it.kind },
        )
    }

    @Test
    fun `chart is dropped entirely when none of its series are supported`() {
        val adapted = DashboardLayout.default.adapted(setOf(TelemetryMetric.SOC))

        assertEquals(listOf(DashboardWidgetKind.Metric(TelemetryMetric.SOC)), adapted.widgets.map { it.kind })
    }

    @Test
    fun `layout round trips through its stored json`() {
        val layout = DashboardLayout(
            listOf(
                DashboardWidgetConfig(
                    DashboardWidgetKind.Metric(TelemetryMetric.BATTERY_TEMP),
                    WidgetStyle.BAR,
                    WidgetSize.LARGE,
                ),
                DashboardWidgetConfig(
                    DashboardWidgetKind.Chart(listOf(TelemetryMetric.POWER, TelemetryMetric.PACK_VOLTAGE)),
                    WidgetStyle.NUMERIC,
                    WidgetSize.LARGE,
                ),
            ),
        )

        assertEquals(layout, DashboardLayout.decode(layout.encode()))
    }

    @Test
    fun `corrupt or absent storage falls back to the default`() {
        assertEquals(DashboardLayout.default, DashboardLayout.decode(null))
        assertEquals(DashboardLayout.default, DashboardLayout.decode("not json"))
        assertEquals(DashboardLayout.default, DashboardLayout.decode("[{\"kind\":{\"type\":\"metric\"}}]"))
    }

    @Test
    fun `half width widgets pair up and full width widgets stand alone`() {
        fun halfMetric(metric: TelemetryMetric) =
            DashboardWidgetConfig(DashboardWidgetKind.Metric(metric), WidgetStyle.NUMERIC, WidgetSize.MEDIUM)

        val soc = DashboardWidgetConfig(
            DashboardWidgetKind.Metric(TelemetryMetric.SOC),
            WidgetStyle.BAR,
            WidgetSize.LARGE,
        )
        val rows = DashboardLayout.packIntoRows(
            listOf(
                halfMetric(TelemetryMetric.SPEED),
                halfMetric(TelemetryMetric.POWER),
                halfMetric(TelemetryMetric.AUX_12V),
                soc,
            ),
        )

        assertEquals(3, rows.size)
        assertEquals(2, rows[0].size)
        assertEquals(1, rows[1].size)
        assertEquals(listOf(soc), rows[2])
    }

    @Test
    fun `untouched layout matches the adapted default`() {
        val supported = setOf(TelemetryMetric.SOC, TelemetryMetric.POWER, TelemetryMetric.SPEED)
        assertTrue(DashboardLayout.default.adapted(supported).matchesDefault(supported))

        val edited = DashboardLayout.default.adapted(supported).widgets.reversed()
        assertFalse(DashboardLayout(edited).matchesDefault(supported))
    }
}
