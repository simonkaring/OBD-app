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
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Vrpano
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.ChargePowerSource
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.components.BatteryLevelBar
import com.simonkaring.voltlink.ui.components.MetricBar
import com.simonkaring.voltlink.ui.components.MetricDial
import com.simonkaring.voltlink.ui.components.NumericTile
import com.simonkaring.voltlink.ui.theme.Theme
import java.util.Locale

/**
 * Live telemetry dashboard. Layout mirrors the iOS default dashboard: power dial, SoC and
 * speed dials, high-voltage pack bar, rolling chart and a grid of secondary metrics.
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
    val profile = manager.selectedProfile
    val history = remember { mutableStateListOf<TelemetrySnapshot>() }

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

    fun available(metric: TelemetryMetric): Boolean {
        // Tiles only show a value once a reading actually decoded, in demo mode too; an
        // unsupported metric reads as "--" instead of a plausible-looking zero.
        if (!isDemoMode && metric !in profile.supportedMetrics) return false
        if (!isDemoMode && !connectionState.isConnected && metric != TelemetryMetric.TRIP_AVERAGE_CONSUMPTION) return false
        return metric.isAvailable(snapshot, liveMetrics, isDemoMode = false)
    }

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
            onOpenDemoControls = onOpenDemoControls,
            onOpenHud = onOpenHud,
        )

        // Primary power dial
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(230.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Theme.cardBackground)
                .padding(12.dp),
            contentAlignment = Alignment.Center,
        ) {
            MetricDial(
                value = units.value(TelemetryMetric.POWER, snapshot),
                range = units.range(TelemetryMetric.POWER),
                unit = units.unit(TelemetryMetric.POWER),
                label = "Power",
                bidirectional = true,
                brush = if (snapshot.powerKW < 0) Theme.regenBrush else Theme.powerBrush,
                isUnavailable = !available(TelemetryMetric.POWER),
                modifier = Modifier.size(210.dp),
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            DialCard(
                modifier = Modifier.weight(1f),
                metric = TelemetryMetric.SOC,
                snapshot = snapshot,
                units = units,
                isAvailable = available(TelemetryMetric.SOC),
                brush = if (snapshot.stateOfChargePct < 20) Theme.socLowBrush else Theme.socBrush,
                statusOverride = "State of charge",
            )
            DialCard(
                modifier = Modifier.weight(1f),
                metric = TelemetryMetric.SPEED,
                snapshot = snapshot,
                units = units,
                isAvailable = available(TelemetryMetric.SPEED),
                brush = Theme.speedBrush,
                statusOverride = "Speed",
            )
        }

        BatteryLevelBar(
            socPct = if (available(TelemetryMetric.SOC)) snapshot.stateOfChargePct else null,
            batteryTempLabel = if (available(TelemetryMetric.BATTERY_TEMP)) {
                String.format(Locale.US, "%.1f %s", units.value(TelemetryMetric.BATTERY_TEMP, snapshot), units.unit(TelemetryMetric.BATTERY_TEMP))
            } else {
                null
            },
            isCharging = snapshot.isCharging,
        )

        LiveTelemetryChart(
            history = history.toList(),
            isUnavailable = !available(TelemetryMetric.POWER) && !available(TelemetryMetric.SPEED),
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricCard(modifier = Modifier.weight(1f)) {
                MetricBar(
                    value = units.value(TelemetryMetric.AUX_12V, snapshot),
                    range = units.range(TelemetryMetric.AUX_12V),
                    unit = units.unit(TelemetryMetric.AUX_12V),
                    label = "Auxiliary 12V",
                    brush = Theme.socBrush,
                    isUnavailable = !available(TelemetryMetric.AUX_12V),
                )
            }
            MetricCard(modifier = Modifier.weight(1f)) {
                MetricBar(
                    value = units.value(TelemetryMetric.BATTERY_TEMP, snapshot),
                    range = units.range(TelemetryMetric.BATTERY_TEMP),
                    unit = units.unit(TelemetryMetric.BATTERY_TEMP),
                    label = "HV Battery Temp",
                    brush = Theme.powerBrush,
                    isUnavailable = !available(TelemetryMetric.BATTERY_TEMP),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricCard(modifier = Modifier.weight(1f)) {
                NumericTile(
                    value = snapshot.motorRpm,
                    unit = "RPM",
                    label = "Motor RPM",
                    metric = TelemetryMetric.MOTOR_RPM,
                    isUnavailable = !available(TelemetryMetric.MOTOR_RPM),
                )
            }
            MetricCard(modifier = Modifier.weight(1f)) {
                NumericTile(
                    value = snapshot.motorTorqueNm,
                    unit = "Nm",
                    label = "Motor Torque",
                    metric = TelemetryMetric.MOTOR_TORQUE,
                    isUnavailable = !available(TelemetryMetric.MOTOR_TORQUE),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricCard(modifier = Modifier.weight(1f)) {
                NumericTile(
                    value = units.value(TelemetryMetric.VEHICLE_RANGE, snapshot),
                    unit = units.unit(TelemetryMetric.VEHICLE_RANGE),
                    label = "Vehicle Range",
                    metric = TelemetryMetric.VEHICLE_RANGE,
                    isUnavailable = !available(TelemetryMetric.VEHICLE_RANGE),
                )
            }
            MetricCard(modifier = Modifier.weight(1f)) {
                NumericTile(
                    value = units.value(TelemetryMetric.INSTANT_EFFICIENCY, snapshot),
                    unit = TelemetryMetric.INSTANT_EFFICIENCY.unitSymbol,
                    label = "Live Consumption",
                    metric = TelemetryMetric.INSTANT_EFFICIENCY,
                    isUnavailable = !available(TelemetryMetric.INSTANT_EFFICIENCY),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            MetricCard(modifier = Modifier.weight(1f)) {
                MetricBar(
                    value = snapshot.chargePowerKW,
                    range = 0.0..150.0,
                    unit = "kW",
                    label = if (snapshot.isCharging) {
                        if (snapshot.chargePowerSource == ChargePowerSource.SOC_ESTIMATE) "Charge power (est.)" else "Charge power"
                    } else {
                        "Charge power"
                    },
                    brush = Theme.socBrush,
                    isUnavailable = !snapshot.isCharging,
                )
            }
            MetricCard(modifier = Modifier.weight(1f)) {
                NumericTile(
                    value = units.value(TelemetryMetric.PACK_VOLTAGE, snapshot),
                    unit = units.unit(TelemetryMetric.PACK_VOLTAGE),
                    label = "Pack Voltage",
                    metric = TelemetryMetric.PACK_VOLTAGE,
                    isUnavailable = !available(TelemetryMetric.PACK_VOLTAGE),
                )
            }
        }

        if (available(TelemetryMetric.COOLANT_TEMP)) {
            MetricCard {
                MetricBar(
                    value = units.value(TelemetryMetric.COOLANT_TEMP, snapshot),
                    range = units.range(TelemetryMetric.COOLANT_TEMP),
                    unit = units.unit(TelemetryMetric.COOLANT_TEMP),
                    label = "Coolant Temp",
                    brush = Theme.powerBrush,
                    isUnavailable = false,
                )
            }
        }
    }
}

@Composable
private fun ConnectionHeader(
    isDemoMode: Boolean,
    connectionState: BleConnectionState,
    vehicleName: String,
    onOpenDemoControls: () -> Unit,
    onOpenHud: () -> Unit,
) {
    val statusColor: Color = when {
        isDemoMode -> Theme.electricCyan
        connectionState.isConnected -> Theme.regenGreen
        else -> Theme.criticalRed
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(statusColor))
        Spacer(Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = when {
                    isDemoMode -> "Demo mode"
                    connectionState is BleConnectionState.Connecting -> "Connecting…"
                    connectionState.isConnected -> "Connected"
                    connectionState is BleConnectionState.Scanning -> "Scanning…"
                    else -> "Disconnected"
                },
                color = Theme.textPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(vehicleName, color = Theme.textSecondary, fontSize = 12.sp)
        }
        HeaderButton(icon = Icons.Filled.Vrpano, label = "HUD", onClick = onOpenHud)
        Spacer(Modifier.width(8.dp))
        HeaderButton(icon = Icons.Filled.Tune, label = "Controls", onClick = onOpenDemoControls)
    }
}

@Composable
private fun HeaderButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Theme.subtleFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 7.dp),
    ) {
        Icon(icon, contentDescription = label, tint = Theme.gaugeCyan, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(5.dp))
        Text(label, color = Theme.textPrimary, fontSize = 12.sp)
    }
}

@Composable
private fun DialCard(
    modifier: Modifier,
    metric: TelemetryMetric,
    snapshot: TelemetrySnapshot,
    units: UnitPrefs,
    isAvailable: Boolean,
    brush: androidx.compose.ui.graphics.Brush,
    statusOverride: String,
) {
    Box(
        modifier = modifier
            .height(184.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Theme.cardBackground)
            .padding(10.dp),
        contentAlignment = Alignment.Center,
    ) {
        MetricDial(
            value = units.value(metric, snapshot),
            range = units.range(metric),
            unit = units.unit(metric),
            label = metric.displayName,
            bidirectional = false,
            brush = brush,
            isUnavailable = !isAvailable,
            statusOverride = statusOverride,
            modifier = Modifier.size(160.dp),
        )
    }
}

@Composable
private fun MetricCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(14.dp),
    ) {
        content()
    }
}

/** Compact charging banner shown while the pack is filling. */
@Composable
fun ChargingBanner(snapshot: TelemetrySnapshot, modifier: Modifier = Modifier) {
    if (!snapshot.isCharging) return
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Bolt, contentDescription = null, tint = Theme.regenGreen)
        Spacer(Modifier.width(8.dp))
        Text(
            text = String.format(Locale.US, "Charging · %.1f kW", snapshot.chargePowerKW),
            color = Theme.textPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.weight(1f))
        Text(
            text = String.format(Locale.US, "%.0f%%", snapshot.stateOfChargePct),
            color = Theme.regenGreen,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
