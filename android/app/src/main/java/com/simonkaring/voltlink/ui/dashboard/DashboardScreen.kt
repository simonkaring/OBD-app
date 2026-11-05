package com.simonkaring.voltlink.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Vrpano
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.DashboardLayout
import com.simonkaring.voltlink.data.DashboardWidgetConfig
import com.simonkaring.voltlink.data.DashboardWidgetKind
import com.simonkaring.voltlink.data.WidgetSize
import com.simonkaring.voltlink.data.WidgetStyle
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.components.BatteryLevelBar
import com.simonkaring.voltlink.ui.components.MetricBar
import com.simonkaring.voltlink.ui.components.MetricDial
import com.simonkaring.voltlink.ui.components.NumericTile
import com.simonkaring.voltlink.ui.theme.Theme
import java.util.Locale

/**
 * Live telemetry dashboard. The widget selection, order and style come from the persisted
 * [DashboardLayout], the same model the iOS dashboard stores; only the connection header and
 * the pack bar are fixed chrome.
 */
@Composable
fun DashboardScreen(
    manager: VehicleDataManager,
    units: UnitPrefs,
    onOpenDemoControls: () -> Unit,
    onOpenHud: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val snapshot by manager.telemetry.collectAsStateWithLifecycle()
    val liveMetrics by manager.liveMetrics.collectAsStateWithLifecycle()
    val connectionState by manager.connectionState.collectAsStateWithLifecycle()
    val isDemoMode by manager.isDemoMode.collectAsStateWithLifecycle()
    val profileId by manager.selectedProfileId.collectAsStateWithLifecycle()
    val layout by manager.settings.dashboardLayout.collectAsStateWithLifecycle()
    val profile = manager.selectedProfile
    val history = remember { mutableStateListOf<TelemetrySnapshot>() }
    var showCustomize by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        // Polling publishes several snapshots per second; the chart only needs 5 Hz.
        var lastSampleAt = 0L
        manager.telemetry.collect {
            val now = System.currentTimeMillis()
            if (now - lastSampleAt < 200) return@collect
            lastSampleAt = now
            history.add(it)
            while (history.size > 50) history.removeAt(0)
        }
    }
    LaunchedEffect(profileId, isDemoMode, connectionState.isConnected) { history.clear() }

    fun available(metric: TelemetryMetric): Boolean = metricAvailable(
        metric = metric,
        snapshot = snapshot,
        liveMetrics = liveMetrics,
        isDemoMode = isDemoMode,
        supportedMetrics = profile.supportedMetrics,
        connectionState = connectionState,
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 14.dp)
            .padding(top = 8.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ConnectionHeader(
            isDemoMode = isDemoMode,
            connectionState = connectionState,
            vehicleName = manager.vehicleDisplayName,
            isCustomized = !layout.matchesDefault(profile.supportedMetrics),
            onOpenCustomize = { showCustomize = true },
            onOpenDemoControls = onOpenDemoControls,
            onOpenHud = onOpenHud,
        )

        BatteryLevelBar(
            socPct = if (available(TelemetryMetric.SOC)) snapshot.stateOfChargePct else null,
            batteryTempLabel = if (available(TelemetryMetric.BATTERY_TEMP)) {
                String.format(
                    Locale.US,
                    "%.1f %s",
                    units.value(TelemetryMetric.BATTERY_TEMP, snapshot),
                    units.unit(TelemetryMetric.BATTERY_TEMP),
                )
            } else {
                null
            },
            isCharging = snapshot.isCharging,
        )

        DashboardLayout.packIntoRows(layout.widgets).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { widget ->
                    DashboardWidgetCard(
                        widget = widget,
                        snapshot = snapshot,
                        units = units,
                        history = history.toList(),
                        liveMetrics = liveMetrics,
                        isDemoMode = isDemoMode,
                        supportedMetrics = profile.supportedMetrics,
                        connectionState = connectionState,
                        modifier = Modifier.weight(1f),
                    )
                }
                // A half-width widget alone in its row keeps the same footprint.
                if (row.size == 1 && row.first().size == WidgetSize.MEDIUM) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }

    if (showCustomize) {
        DashboardCustomizationSheet(
            layout = layout,
            supportedMetrics = profile.supportedMetrics,
            liveMetrics = liveMetrics,
            profileName = manager.vehicleDisplayName,
            isConnected = connectionState.isConnected,
            isDemoMode = isDemoMode,
            onChange = { manager.settings.setDashboardLayout(it) },
            onDismiss = { showCustomize = false },
        )
    }
}

/** Whether a metric can be shown right now: profile support, connection, and freshness. */
internal fun metricAvailable(
    metric: TelemetryMetric,
    snapshot: TelemetrySnapshot,
    liveMetrics: Set<TelemetryMetric>,
    isDemoMode: Boolean,
    supportedMetrics: Set<TelemetryMetric>,
    connectionState: BleConnectionState,
): Boolean {
    // Tiles only show a value once a reading actually decoded, in demo mode too; an
    // unsupported metric reads as "--" instead of a plausible-looking zero.
    if (!isDemoMode && metric !in supportedMetrics) return false
    if (!isDemoMode && !connectionState.isConnected && metric != TelemetryMetric.TRIP_AVERAGE_CONSUMPTION) return false
    return metric.isAvailable(snapshot, liveMetrics, isDemoMode = false)
}

@Composable
private fun DashboardWidgetCard(
    widget: DashboardWidgetConfig,
    snapshot: TelemetrySnapshot,
    units: UnitPrefs,
    history: List<TelemetrySnapshot>,
    liveMetrics: Set<TelemetryMetric>,
    isDemoMode: Boolean,
    supportedMetrics: Set<TelemetryMetric>,
    connectionState: BleConnectionState,
    modifier: Modifier = Modifier,
) {
    fun available(metric: TelemetryMetric): Boolean = metricAvailable(
        metric = metric,
        snapshot = snapshot,
        liveMetrics = liveMetrics,
        isDemoMode = isDemoMode,
        supportedMetrics = supportedMetrics,
        connectionState = connectionState,
    )

    when (val kind = widget.kind) {
        is DashboardWidgetKind.Chart -> {
            LiveTelemetryChart(
                history = history,
                units = units,
                series = kind.series,
                modifier = modifier,
                isUnavailable = kind.series.none { available(it) },
            )
        }
        is DashboardWidgetKind.Metric -> {
            val metric = kind.metric
            val value = units.value(metric, snapshot)
            val height = when (widget.style) {
                WidgetStyle.DIAL -> if (widget.size == WidgetSize.LARGE) 236.dp else 190.dp
                else -> null
            }
            Box(
                modifier = modifier
                    .then(if (height != null) Modifier.height(height) else Modifier)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Theme.cardBackground)
                    .padding(14.dp),
                contentAlignment = if (widget.style == WidgetStyle.DIAL) Alignment.Center else Alignment.TopStart,
            ) {
                val isAvailable = available(metric)
                when (widget.style) {
                    WidgetStyle.DIAL -> MetricDial(
                        value = value,
                        range = units.range(metric),
                        unit = units.unit(metric),
                        label = metric.displayName,
                        bidirectional = metric == TelemetryMetric.POWER,
                        brush = brushFor(metric, snapshot),
                        isUnavailable = !isAvailable,
                        modifier = Modifier.size(dialSize(widget.size)),
                    )
                    WidgetStyle.BAR -> MetricBar(
                        value = value,
                        range = units.range(metric),
                        unit = units.unit(metric),
                        label = metric.displayName,
                        brush = brushFor(metric, snapshot),
                        isUnavailable = !isAvailable,
                    )
                    WidgetStyle.NUMERIC -> NumericTile(
                        value = value,
                        unit = units.unit(metric),
                        label = metric.displayName,
                        metric = metric,
                        isUnavailable = !isAvailable,
                    )
                }
            }
        }
    }
}

private fun dialSize(size: WidgetSize): Dp = if (size == WidgetSize.LARGE) 210.dp else 166.dp

private fun brushFor(metric: TelemetryMetric, snapshot: TelemetrySnapshot): Brush = when {
    metric == TelemetryMetric.POWER && snapshot.powerKW < 0 -> Theme.regenBrush
    metric == TelemetryMetric.POWER -> Theme.powerBrush
    metric == TelemetryMetric.SOC && snapshot.stateOfChargePct < 20 -> Theme.socLowBrush
    else -> Theme.socBrush
}

@Composable
private fun ConnectionHeader(
    isDemoMode: Boolean,
    connectionState: BleConnectionState,
    vehicleName: String,
    isCustomized: Boolean,
    onOpenCustomize: () -> Unit,
    onOpenDemoControls: () -> Unit,
    onOpenHud: () -> Unit,
) {
    val statusColor: Color = when {
        isDemoMode -> Theme.electricCyan
        connectionState.isConnected -> Theme.regenGreen
        else -> Theme.criticalRed
    }
    // The status line owns a full row so a long vehicle name ellipsizes instead of wrapping
    // into the action chips; the chips get their own row underneath.
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(statusColor))
            Spacer(Modifier.width(7.dp))
            Text(
                text = when {
                    isDemoMode -> stringResource(R.string.dashboard_status_demo)
                    connectionState is BleConnectionState.Connecting -> stringResource(R.string.dashboard_status_connecting)
                    connectionState.isConnected -> stringResource(R.string.dashboard_status_connected)
                    connectionState is BleConnectionState.Scanning -> stringResource(R.string.dashboard_status_scanning)
                    else -> stringResource(R.string.dashboard_status_disconnected)
                },
                color = Theme.textPrimary,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.width(10.dp))
            Text(
                text = vehicleName,
                color = Theme.textSecondary,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.End,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HeaderButton(
                icon = Icons.Filled.GridView,
                label = stringResource(R.string.dashboard_button_layout),
                tint = if (isCustomized) Theme.electricCyan else Theme.textSecondary,
                onClick = onOpenCustomize,
            )
            HeaderButton(
                icon = Icons.Filled.Vrpano,
                label = stringResource(R.string.dashboard_button_hud),
                onClick = onOpenHud,
            )
            HeaderButton(
                icon = Icons.Filled.Tune,
                label = stringResource(R.string.dashboard_button_controls),
                onClick = onOpenDemoControls,
            )
        }
    }
}

@Composable
private fun HeaderButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
    tint: Color = Theme.textSecondary,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Theme.subtleFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 7.dp),
    ) {
        Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(15.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, color = Theme.textPrimary, fontSize = 12.sp)
    }
}
