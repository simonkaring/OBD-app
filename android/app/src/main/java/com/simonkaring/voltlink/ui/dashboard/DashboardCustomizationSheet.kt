package com.simonkaring.voltlink.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.annotation.StringRes
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.data.DashboardLayout
import com.simonkaring.voltlink.data.DashboardWidgetConfig
import com.simonkaring.voltlink.data.DashboardWidgetKind
import com.simonkaring.voltlink.data.WidgetSize
import com.simonkaring.voltlink.data.WidgetStyle
import com.simonkaring.voltlink.ui.theme.Theme

/**
 * Reorder/add/remove editor for the dashboard layout. Every change is applied immediately
 * through [onChange], so the sheet can be dismissed at any point without losing edits.
 */
@Composable
fun DashboardCustomizationSheet(
    layout: DashboardLayout,
    supportedMetrics: Set<TelemetryMetric>,
    liveMetrics: Set<TelemetryMetric>,
    profileName: String,
    isConnected: Boolean,
    isDemoMode: Boolean,
    onChange: (DashboardLayout) -> Unit,
    onDismiss: () -> Unit,
) {
    fun update(widgets: List<DashboardWidgetConfig>) = onChange(DashboardLayout(widgets))

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .fillMaxHeight(0.9f)
                .clip(RoundedCornerShape(20.dp))
                .background(Theme.backgroundDark)
                .padding(16.dp),
        ) {
            Text(
                stringResource(R.string.dashboard_customize_title),
                color = Theme.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(profileName, color = Theme.electricCyan, fontSize = 12.sp)
            Spacer(Modifier.height(4.dp))
            Text(
                stringResource(R.string.dashboard_customize_hint),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
            Spacer(Modifier.height(10.dp))

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                itemsIndexed(layout.widgets) { index, widget ->
                    WidgetEditorRow(
                        widget = widget,
                        status = widgetStatus(widget, supportedMetrics, liveMetrics, isConnected, isDemoMode),
                        canMoveUp = index > 0,
                        canMoveDown = index < layout.widgets.lastIndex,
                        onMoveUp = {
                            val widgets = layout.widgets.toMutableList()
                            widgets.add(index - 1, widgets.removeAt(index))
                            update(widgets)
                        },
                        onMoveDown = {
                            val widgets = layout.widgets.toMutableList()
                            widgets.add(index + 1, widgets.removeAt(index))
                            update(widgets)
                        },
                        onRemove = { update(layout.widgets.filterIndexed { i, _ -> i != index }) },
                        onStyle = { style -> update(layout.widgets.replaceAt(index, widget.copy(style = style))) },
                        onSize = { size -> update(layout.widgets.replaceAt(index, widget.copy(size = size))) },
                    )
                }

                item {
                    val missing = supportedMetrics
                        .filter { metric -> layout.widgets.none { it.kind == DashboardWidgetKind.Metric(metric) } }
                        .sortedBy { it.displayName }
                    Text(
                        stringResource(R.string.dashboard_add_widget),
                        color = Theme.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                    if (missing.isEmpty()) {
                        Text(
                            stringResource(R.string.dashboard_all_widgets_added),
                            color = Theme.textSecondary,
                            fontSize = 11.sp,
                        )
                    } else {
                        missing.forEach { metric ->
                            AddRow(metric.displayName) {
                                update(
                                    layout.widgets + DashboardWidgetConfig(
                                        DashboardWidgetKind.Metric(metric),
                                        WidgetStyle.NUMERIC,
                                        WidgetSize.MEDIUM,
                                    ),
                                )
                            }
                        }
                    }
                    val chartSupported = listOf(TelemetryMetric.POWER, TelemetryMetric.SPEED)
                        .filter { it in supportedMetrics }
                    if (chartSupported.isNotEmpty()) {
                        AddRow(
                            stringResource(
                                R.string.dashboard_add_chart,
                                chartSupported.joinToString(" & ") { it.displayName },
                            ),
                        ) {
                            update(
                                layout.widgets + DashboardWidgetConfig(
                                    DashboardWidgetKind.Chart(chartSupported),
                                    WidgetStyle.NUMERIC,
                                    WidgetSize.LARGE,
                                ),
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { onChange(DashboardLayout.default) }) {
                    Text(stringResource(R.string.action_reset), color = Theme.textSecondary, fontSize = 13.sp)
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.action_done), color = Theme.electricCyan, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

/** Compatibility/liveness label for one widget row, mirroring the iOS sheet copy. */
private fun widgetStatus(
    widget: DashboardWidgetConfig,
    supportedMetrics: Set<TelemetryMetric>,
    liveMetrics: Set<TelemetryMetric>,
    isConnected: Boolean,
    isDemoMode: Boolean,
): Pair<Int, Boolean> {
    val metrics = widget.metrics
    val compatible = metrics.all { it in supportedMetrics }
    if (!compatible) return R.string.status_incompatible to false
    if (!isConnected && !isDemoMode) return R.string.status_compatible_not_connected to true
    val live = isDemoMode || metrics.all { it in liveMetrics }
    return (if (live) R.string.status_live else R.string.status_compatible_no_data) to true
}

@Composable
private fun WidgetEditorRow(
    widget: DashboardWidgetConfig,
    status: Pair<Int, Boolean>,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onRemove: () -> Unit,
    onStyle: (WidgetStyle) -> Unit,
    onSize: (WidgetSize) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Theme.cardBackground)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(widget.title, color = Theme.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    stringResource(status.first),
                    color = if (status.second) Theme.textSecondary else Theme.highPowerAmber,
                    fontSize = 10.sp,
                )
            }
            IconButton(onClick = onMoveUp, enabled = canMoveUp, modifier = Modifier.size(30.dp)) {
                Icon(
                    Icons.Filled.KeyboardArrowUp,
                    contentDescription = stringResource(R.string.action_move_up),
                    tint = if (canMoveUp) Theme.textSecondary else Theme.trackBackground,
                    modifier = Modifier.size(18.dp),
                )
            }
            IconButton(onClick = onMoveDown, enabled = canMoveDown, modifier = Modifier.size(30.dp)) {
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = stringResource(R.string.action_move_down),
                    tint = if (canMoveDown) Theme.textSecondary else Theme.trackBackground,
                    modifier = Modifier.size(18.dp),
                )
            }
            IconButton(onClick = onRemove, modifier = Modifier.size(30.dp)) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = stringResource(R.string.dashboard_remove_widget),
                    tint = Theme.textSecondary,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (widget.kind is DashboardWidgetKind.Metric) {
                WidgetStyle.entries.forEach { style ->
                    ChoiceChip(stringResource(styleLabel(style)), widget.style == style) { onStyle(style) }
                }
            }
            Spacer(Modifier.weight(1f))
            ChoiceChip(stringResource(R.string.widget_size_half), widget.size == WidgetSize.MEDIUM) {
                onSize(WidgetSize.MEDIUM)
            }
            ChoiceChip(stringResource(R.string.widget_size_full), widget.size == WidgetSize.LARGE) {
                onSize(WidgetSize.LARGE)
            }
        }
    }
}

@Composable
private fun ChoiceChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text = label,
        color = if (selected) Theme.onAccent else Theme.textSecondary,
        fontSize = 11.sp,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) Theme.electricCyan else Theme.subtleFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 9.dp, vertical = 5.dp),
    )
}

@Composable
private fun AddRow(label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 34.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Theme.faintFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = Theme.textPrimary, fontSize = 12.sp, modifier = Modifier.weight(1f))
        Icon(
            Icons.Filled.Add,
            contentDescription = stringResource(R.string.action_add),
            tint = Theme.electricCyan,
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(2.dp))
    }
}

@StringRes
private fun styleLabel(style: WidgetStyle): Int = when (style) {
    WidgetStyle.NUMERIC -> R.string.widget_style_number
    WidgetStyle.DIAL -> R.string.widget_style_dial
    WidgetStyle.BAR -> R.string.widget_style_bar
}

private fun List<DashboardWidgetConfig>.replaceAt(index: Int, value: DashboardWidgetConfig): List<DashboardWidgetConfig> =
    toMutableList().also { it[index] = value }
