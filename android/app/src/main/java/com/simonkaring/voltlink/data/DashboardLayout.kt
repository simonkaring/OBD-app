package com.simonkaring.voltlink.data

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A dashboard widget: one telemetry metric, or a chart of up to two metrics. */
@Serializable
sealed interface DashboardWidgetKind {
    @Serializable
    @SerialName("metric")
    data class Metric(val metric: TelemetryMetric) : DashboardWidgetKind

    @Serializable
    @SerialName("chart")
    data class Chart(val series: List<TelemetryMetric>) : DashboardWidgetKind
}

/** How a metric widget draws its value; charts always use the plot. */
@Serializable
enum class WidgetStyle { NUMERIC, DIAL, BAR }

/** Half-width widgets pair up two per row; full-width widgets take a row of their own. */
@Serializable
enum class WidgetSize { MEDIUM, LARGE }

@Serializable
data class DashboardWidgetConfig(
    val kind: DashboardWidgetKind,
    val style: WidgetStyle,
    val size: WidgetSize,
) {
    /** Every metric this widget reads, in display order. */
    val metrics: List<TelemetryMetric>
        get() = when (val current = kind) {
            is DashboardWidgetKind.Metric -> listOf(current.metric)
            is DashboardWidgetKind.Chart -> current.series
        }

    val title: String
        get() = when (val current = kind) {
            is DashboardWidgetKind.Metric -> current.metric.displayName
            is DashboardWidgetKind.Chart -> "Chart (${current.series.joinToString(" & ") { it.displayName }})"
        }
}

/**
 * The user's dashboard order and selection, persisted as JSON like the iOS `DashboardLayout`.
 * Widget identity is positional — the layout is compared by kind, style and size, never by ID.
 */
data class DashboardLayout(val widgets: List<DashboardWidgetConfig>) {
    /**
     * Drops widgets whose metrics the selected profile never reports, and narrows chart series
     * the same way, so a fresh dashboard does not open with unsupported warning tiles.
     */
    fun adapted(supportedMetrics: Set<TelemetryMetric>): DashboardLayout =
        DashboardLayout(
            widgets.mapNotNull { widget ->
                when (val kind = widget.kind) {
                    is DashboardWidgetKind.Metric ->
                        widget.takeIf { kind.metric in supportedMetrics }
                    is DashboardWidgetKind.Chart -> {
                        val supported = kind.series.filter { it in supportedMetrics }
                        widget.takeIf { supported.isNotEmpty() }
                            ?.copy(kind = DashboardWidgetKind.Chart(supported))
                    }
                }
            },
        )

    /** True when the user has not changed the default selection or order. */
    fun matchesDefault(supportedMetrics: Set<TelemetryMetric>): Boolean {
        val defaults = default.adapted(supportedMetrics).widgets
        return widgets.size == defaults.size &&
            widgets.zip(defaults).all { (actual, expected) ->
                actual.kind == expected.kind && actual.style == expected.style && actual.size == expected.size
            }
    }

    fun encode(): String = json.encodeToString(widgets)

    companion object {
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        /** Familiar driving and charging readouts plus the rolling telemetry chart. */
        val default = DashboardLayout(
            widgets = listOf(
                DashboardWidgetConfig(DashboardWidgetKind.Metric(TelemetryMetric.SPEED), WidgetStyle.DIAL, WidgetSize.MEDIUM),
                DashboardWidgetConfig(DashboardWidgetKind.Metric(TelemetryMetric.POWER), WidgetStyle.DIAL, WidgetSize.MEDIUM),
                DashboardWidgetConfig(DashboardWidgetKind.Metric(TelemetryMetric.SOC), WidgetStyle.BAR, WidgetSize.LARGE),
                DashboardWidgetConfig(DashboardWidgetKind.Metric(TelemetryMetric.AUX_12V), WidgetStyle.NUMERIC, WidgetSize.MEDIUM),
                DashboardWidgetConfig(
                    DashboardWidgetKind.Chart(listOf(TelemetryMetric.POWER, TelemetryMetric.SPEED)),
                    WidgetStyle.NUMERIC,
                    WidgetSize.LARGE,
                ),
            ),
        )

        /** Decodes a stored layout, falling back to the default for absent or corrupt values. */
        fun decode(raw: String?): DashboardLayout {
            if (raw.isNullOrBlank()) return default
            return runCatching { DashboardLayout(json.decodeFromString<List<DashboardWidgetConfig>>(raw)) }
                .getOrElse { default }
        }

        /** Packs widgets into rows: two half-width widgets pair up, full-width ones stand alone. */
        fun packIntoRows(widgets: List<DashboardWidgetConfig>): List<List<DashboardWidgetConfig>> {
            val rows = mutableListOf<List<DashboardWidgetConfig>>()
            var pending: DashboardWidgetConfig? = null
            for (widget in widgets) {
                if (widget.size == WidgetSize.MEDIUM) {
                    if (pending == null) {
                        pending = widget
                    } else {
                        rows += listOf(pending, widget)
                        pending = null
                    }
                } else {
                    pending?.let { rows += listOf(it) }
                    pending = null
                    rows += listOf(widget)
                }
            }
            pending?.let { rows += listOf(it) }
            return rows
        }
    }
}
