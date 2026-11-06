package com.simonkaring.voltlink.ui.charging

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.export.ExportShare
import com.simonkaring.voltlink.core.export.TripExport
import com.simonkaring.voltlink.core.history.ChargingHistoryInsights
import com.simonkaring.voltlink.core.telemetry.ChargePowerSource
import com.simonkaring.voltlink.core.telemetry.ChargingCurveSample
import com.simonkaring.voltlink.core.telemetry.ChargingSessionMath
import com.simonkaring.voltlink.core.telemetry.ChargingTimeEstimator
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.BatteryHealthRecord
import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.HistoryStore
import com.simonkaring.voltlink.services.ChargingTracker
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.components.EmptyState
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.text.NumberFormat
import java.util.Locale

private val sessionDateFormatter = DateTimeFormatter.ofPattern("d MMM HH:mm").withZone(ZoneId.systemDefault())
private val sessionTimeFormatter = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())

/**
 * Charging tab: the live session (power, elapsed time, average, both ETAs, pack state), usable
 * capacity, battery health, and a session history with a monthly summary and a detail sheet.
 */
@Composable
fun ChargingScreen(
    manager: VehicleDataManager,
    tracker: ChargingTracker,
    store: HistoryStore,
    units: UnitPrefs = UnitPrefs(),
    modifier: Modifier = Modifier,
) {
    val state by tracker.state.collectAsStateWithLifecycle()
    val sessions by tracker.history.collectAsStateWithLifecycle()
    val health by store.batteryHealth.collectAsStateWithLifecycle()
    val snapshot by manager.telemetry.collectAsStateWithLifecycle()
    val liveMetrics by manager.liveMetrics.collectAsStateWithLifecycle()
    val isDemoMode by manager.isDemoMode.collectAsStateWithLifecycle()
    val target by manager.settings.chargeTargetPercent.collectAsStateWithLifecycle()
    val pricePerKWh by manager.settings.tripCostPerKWh.collectAsStateWithLifecycle()
    val profileId by manager.selectedProfileId.collectAsStateWithLifecycle()
    val capacityKWh = remember(profileId) { manager.selectedProfile.batteryUsableCapacityKWh }

    var selectedSessionId by remember { mutableStateOf<String?>(null) }
    val selectedSession = selectedSessionId?.let { id -> sessions.firstOrNull { it.id == id } }

    val charging = state.isCharging
    val session = state.current
    val soc = snapshot.stateOfChargePct
    val capacity = capacityKWh.takeIf { it.isFinite() && it > 0.0 }
    val elapsedSeconds = session?.let {
        Duration.between(it.startTime, snapshot.timestamp).seconds.toDouble().coerceAtLeast(0.0)
    }
    val averagePower = session?.let {
        ChargingSessionMath.averagePowerKW(it.totalKWhDelivered, it.startTime, snapshot.timestamp)
    }
    val observedCurve = session?.samples.orEmpty().map { ChargingCurveSample(it.socPct, it.powerKW) }
    fun estimateTo(targetSoc: Double): Double? {
        if (!charging || capacity == null) return null
        return ChargingTimeEstimator.secondsToTarget(
            currentSoc = soc,
            targetSoc = targetSoc,
            currentPowerKW = snapshot.chargePowerKW,
            capacityKWh = capacity,
            observedCurve = observedCurve,
        )
    }

    val estimated = snapshot.chargePowerSource == ChargePowerSource.SOC_ESTIMATE
    val statusText = when {
        charging && estimated -> stringResource(R.string.charging_status_estimated)
        charging -> stringResource(R.string.charging_status_charging)
        else -> stringResource(R.string.charging_status_not_charging)
    }
    val powerLabel = when {
        estimated -> stringResource(R.string.charging_power_estimated)
        snapshot.chargePowerKW > ChargingTimeEstimator.DC_POWER_THRESHOLD_KW ->
            stringResource(R.string.charging_dc_power)
        else -> stringResource(R.string.charging_power)
    }
    val secondsToTarget = state.secondsToTarget ?: estimateTo(target.toDouble())
    val secondsToFull = estimateTo(100.0)
    val monthlyInsights = remember(sessions, pricePerKWh) {
        ChargingHistoryInsights.summarize(sessions, ChargingHistoryInsights.startOfMonth(), pricePerKWh)
    }
    val isShown: (TelemetryMetric) -> Boolean = {
        it.isAvailable(snapshot, liveMetrics, isDemoMode)
    }

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp),
    ) {
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Theme.cardBackground)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (charging) Icons.Filled.Bolt else Icons.Filled.BatteryChargingFull,
                        contentDescription = null,
                        tint = if (charging) Theme.regenGreen else Theme.textSecondary,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = statusText,
                        color = if (charging) Theme.regenGreen else Theme.textPrimary,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                    )
                    ChargeTargetMenu(target) { manager.settings.setChargeTargetPercent(it) }
                }

                Text(
                    text = stringResource(R.string.charging_soc_percent, soc),
                    color = when {
                        soc < 20 -> Theme.criticalRed
                        charging -> Theme.regenGreen
                        else -> Theme.gaugeCyan
                    },
                    fontSize = 40.sp,
                    fontWeight = FontWeight.Bold,
                )

                // SOC bar with the start-of-charge tick and the target marker, both drawn in one
                // Canvas so neither can stretch into a filled block of its own.
                Canvas(modifier = Modifier.fillMaxWidth().height(14.dp)) {
                    val radius = size.height / 2
                    drawRoundRect(
                        color = Theme.trackBackground,
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius, radius),
                    )
                    val fraction = (soc.coerceIn(0.0, 100.0) / 100.0).toFloat()
                    if (fraction > 0f) {
                        drawRoundRect(
                            color = if (snapshot.isCharging) Theme.regenGreen else Theme.gaugeCyan,
                            size = androidx.compose.ui.geometry.Size(size.width * fraction, size.height),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius, radius),
                        )
                    }
                    val startSoc = session?.startSocPct?.takeIf { charging }?.coerceIn(0.0, 100.0)
                    if (startSoc != null && startSoc <= soc) {
                        drawRect(
                            color = Theme.textSecondary.copy(alpha = 0.8f),
                            topLeft = Offset(size.width * (startSoc / 100.0).toFloat() - 1.dp.toPx(), 0f),
                            size = androidx.compose.ui.geometry.Size(2.dp.toPx(), size.height),
                        )
                    }
                    val targetX = size.width * (target.coerceIn(0, 100) / 100f)
                    drawRect(
                        color = Theme.textPrimary,
                        topLeft = Offset(targetX - 1.dp.toPx(), 0f),
                        size = androidx.compose.ui.geometry.Size(2.dp.toPx(), size.height),
                    )
                }

                if (charging && session != null) {
                    Text(
                        text = stringResource(R.string.charging_session_soc, session.startSocPct, soc) + " · " +
                            stringResource(R.string.charging_gained, (soc - session.startSocPct).coerceAtLeast(0.0)),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ChargeStat(
                        formatPower(snapshot.chargePowerKW, units),
                        powerLabel,
                        Modifier.weight(1f),
                    )
                    ChargeStat(
                        if (charging) formatElapsed(elapsedSeconds ?: 0.0) else "—",
                        stringResource(R.string.charging_elapsed),
                        Modifier.weight(1f),
                    )
                    ChargeStat(
                        averagePower?.let { formatPower(it, units) } ?: "—",
                        stringResource(R.string.charging_average_power),
                        Modifier.weight(1f),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ChargeStat(
                        etaValue(secondsToTarget),
                        stringResource(R.string.charging_to_target, target),
                        Modifier.weight(1f),
                    )
                    ChargeStat(
                        etaValue(secondsToFull),
                        stringResource(R.string.charging_to_full),
                        Modifier.weight(1f),
                    )
                    ChargeStat(
                        String.format(Locale.US, "%.1f kWh", session?.totalKWhDelivered ?: 0.0),
                        stringResource(R.string.charging_delivered),
                        Modifier.weight(1f),
                    )
                }

                if (charging && estimated) {
                    Text(
                        stringResource(R.string.charging_estimated_caveat),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }
                if (charging && secondsToTarget == null) {
                    Text(
                        stringResource(R.string.charging_eta_needs_power),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }

                val livePoints = session?.samples
                    ?.let { ChargingSpeedCurve.session(it.takeLast(180)) }
                    .orEmpty()
                if (livePoints.size >= 2) {
                    ChargingSpeedChart(points = livePoints, units = units)
                }

                val lastSession = sessions.firstOrNull()
                if (!charging && lastSession != null) {
                    Text(
                        stringResource(
                            R.string.charging_last_session,
                            sessionDateFormatter.format(lastSession.startTime),
                            String.format(Locale.US, "%.1f kWh", lastSession.totalKWhDelivered),
                        ),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }
            }
        }

        if (capacity != null) {
            item { CapacityCard(capacity, soc) }
        }

        if (listOf(
                TelemetryMetric.PACK_VOLTAGE,
                TelemetryMetric.PACK_CURRENT,
                TelemetryMetric.BATTERY_TEMP,
                TelemetryMetric.BATTERY_TEMP_MIN,
                TelemetryMetric.BATTERY_TEMP_MAX,
            ).any(isShown)
        ) {
            item { PackCard(snapshot, units, isShown) }
        }

        if (health.size >= 2) {
            item { BatteryHealthCard(health) }
        }

        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.Bolt,
                    contentDescription = null,
                    tint = Theme.textSecondary,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    stringResource(R.string.charging_history_title),
                    color = Theme.textPrimary,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        if (monthlyInsights.sessionCount > 0) {
            item { ChargingMonthCard(monthlyInsights) }
        }

        if (sessions.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Filled.Bolt,
                    title = stringResource(R.string.charging_history_empty_title),
                    message = stringResource(R.string.charging_history_empty),
                )
            }
        }

        items(sessions, key = { it.id }) { record ->
            SessionCard(record, units, pricePerKWh) { selectedSessionId = record.id }
        }
    }

    if (selectedSession != null) {
        SessionDetailSheet(
            session = selectedSession,
            units = units,
            pricePerKWh = pricePerKWh,
            onDismiss = { selectedSessionId = null },
            onDelete = {
                tracker.deleteSession(selectedSession.id)
                selectedSessionId = null
            },
        )
    }
}

@Composable
private fun ChargeTargetMenu(target: Int, onSelect: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(
            onClick = { expanded = true },
            contentPadding = PaddingValues(horizontal = 6.dp, vertical = 0.dp),
        ) {
            Text(
                stringResource(R.string.charging_target, target),
                color = Theme.electricCyan,
                fontSize = 12.sp,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            listOf(50, 60, 70, 80, 90, 100).forEach { option ->
                DropdownMenuItem(
                    text = { Text("$option%") },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                )
            }
        }
    }
}

@Composable
private fun ChargeStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(value, color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Text(label, color = Theme.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun etaValue(seconds: Double?): String = when {
    seconds == null -> "—"
    seconds <= 0.0 -> stringResource(R.string.charging_reached)
    else -> formatElapsed(seconds)
}

private fun formatPower(kilowatts: Double, units: UnitPrefs): String =
    String.format(Locale.US, "%.1f %s", units.powerValue(kilowatts), units.powerUnitLabel)

private fun formatTemperature(celsius: Double, units: UnitPrefs): String =
    String.format(Locale.US, "%.0f %s", units.temperatureValue(celsius), units.temperatureUnitLabel)

private fun formatDistance(km: Double, units: UnitPrefs): String =
    String.format(Locale.US, "%.0f %s", units.distanceValue(km), units.distanceUnitLabel)

@Composable
private fun CapacityCard(capacityKWh: Double, socPct: Double) {
    val soc = socPct.coerceIn(0.0, 100.0)
    val stored = capacityKWh * soc / 100.0
    val toFull = capacityKWh * (100.0 - soc) / 100.0
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            stringResource(R.string.charging_capacity_title),
            color = Theme.textPrimary,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ChargeStat(
                String.format(Locale.US, "%.1f kWh", capacityKWh),
                stringResource(R.string.charging_usable_capacity),
                Modifier.weight(1f),
            )
            ChargeStat(
                String.format(Locale.US, "%.1f kWh", stored),
                stringResource(R.string.charging_stored_energy),
                Modifier.weight(1f),
            )
            ChargeStat(
                String.format(Locale.US, "%.1f kWh", toFull),
                stringResource(R.string.charging_energy_to_full),
                Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun PackCard(
    snapshot: TelemetrySnapshot,
    units: UnitPrefs,
    isShown: (TelemetryMetric) -> Boolean,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            stringResource(R.string.charging_pack_title),
            color = Theme.textPrimary,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (isShown(TelemetryMetric.PACK_VOLTAGE)) {
                ChargeStat(
                    String.format(Locale.US, "%.1f V", snapshot.voltageV),
                    stringResource(R.string.charging_pack_voltage),
                    Modifier.weight(1f),
                )
            }
            if (isShown(TelemetryMetric.PACK_CURRENT)) {
                ChargeStat(
                    String.format(Locale.US, "%.1f A", snapshot.currentA),
                    stringResource(R.string.charging_pack_current),
                    Modifier.weight(1f),
                )
            }
            if (isShown(TelemetryMetric.BATTERY_TEMP)) {
                ChargeStat(
                    formatTemperature(snapshot.batteryTempC, units),
                    stringResource(R.string.charging_battery_temp),
                    Modifier.weight(1f),
                )
            }
        }
        if (isShown(TelemetryMetric.BATTERY_TEMP_MIN) && isShown(TelemetryMetric.BATTERY_TEMP_MAX)) {
            Text(
                stringResource(
                    R.string.charging_temp_range,
                    formatTemperature(snapshot.batteryTempMinC, units),
                    formatTemperature(snapshot.batteryTempMaxC, units),
                ),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
    }
}

@Composable
private fun ChargingMonthCard(insights: ChargingHistoryInsights) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.charging_month),
                color = Theme.electricCyan,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.weight(1f))
            Text(
                if (insights.sessionCount == 1) {
                    stringResource(R.string.charging_session_count_one)
                } else {
                    stringResource(R.string.charging_session_count_many, insights.sessionCount)
                },
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ChargeStat(
                String.format(Locale.US, "%.1f kWh", insights.energyKWh),
                stringResource(R.string.charging_stat_energy),
                Modifier.weight(1f),
            )
            if (insights.hasCost) {
                ChargeStat(
                    NumberFormat.getCurrencyInstance().format(insights.cost),
                    stringResource(R.string.charging_stat_cost),
                    Modifier.weight(1f),
                )
            }
            ChargeStat(
                stringResource(
                    R.string.charging_acdc_value,
                    insights.acSessions,
                    insights.dcSessions,
                ),
                stringResource(R.string.charging_stat_acdc),
                Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun SessionCard(
    session: ChargingSessionRecord,
    units: UnitPrefs,
    pricePerKWh: Double,
    onOpen: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .clickable(onClick = onOpen)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                sessionDateFormatter.format(session.startTime),
                color = Theme.textSecondary,
                fontSize = 12.sp,
                modifier = Modifier.weight(1f),
            )
            ChargerTypeChip(session.isDCCharging)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ChargeStat(
                String.format(Locale.US, "%.0f%% → %.0f%%", session.startSocPct, session.endSocPct),
                stringResource(R.string.charging_stat_state_of_charge),
                Modifier.weight(1f),
            )
            ChargeStat(
                String.format(Locale.US, "%.1f kWh", session.totalKWhDelivered),
                stringResource(R.string.charging_delivered),
                Modifier.weight(1f),
            )
            ChargeStat(
                formatPower(session.peakPowerKW, units),
                stringResource(R.string.charging_stat_peak),
                Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ChargeStat(
                formatPower(session.averagePowerKW, units),
                stringResource(R.string.charging_average_power),
                Modifier.weight(1f),
            )
            ChargeStat(
                formatElapsed(session.duration.seconds.toDouble()),
                stringResource(R.string.charging_stat_duration),
                Modifier.weight(1f),
            )
            if (pricePerKWh > 0) {
                ChargeStat(
                    String.format(Locale.US, "%.2f", session.totalKWhDelivered * pricePerKWh),
                    stringResource(R.string.charging_stat_cost),
                    Modifier.weight(1f),
                )
            } else {
                Spacer(Modifier.weight(1f))
            }
        }
        val points = ChargingSpeedCurve.session(session.samples)
        if (points.size >= 2) {
            ChargingSpeedChart(points = points, units = units)
            Text(
                stringResource(R.string.charging_speed_over_time),
                color = Theme.textSecondary,
                fontSize = 10.sp,
            )
        }
    }
}

@Composable
private fun ChargerTypeChip(isDC: Boolean) {
    val color = if (isDC) Theme.highPowerAmber else Theme.gaugeCyan
    Text(
        text = stringResource(if (isDC) R.string.charging_dc else R.string.charging_ac),
        color = color,
        fontSize = 10.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .background(color.copy(alpha = 0.18f), RoundedCornerShape(4.dp))
            .padding(horizontal = 5.dp, vertical = 2.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SessionDetailSheet(
    session: ChargingSessionRecord,
    units: UnitPrefs,
    pricePerKWh: Double,
    onDismiss: () -> Unit,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.charging_detail_title),
                        color = Theme.textPrimary,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        session.endTime?.let {
                            stringResource(
                                R.string.charging_detail_time,
                                sessionDateFormatter.format(session.startTime),
                                sessionTimeFormatter.format(it),
                            )
                        } ?: sessionDateFormatter.format(session.startTime),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }
                ChargerTypeChip(session.isDCCharging)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ChargeStat(
                    String.format(Locale.US, "%.0f%% → %.0f%%", session.startSocPct, session.endSocPct),
                    stringResource(R.string.charging_stat_state_of_charge),
                    Modifier.weight(1f),
                )
                ChargeStat(
                    String.format(Locale.US, "%.1f kWh", session.totalKWhDelivered),
                    stringResource(R.string.charging_delivered),
                    Modifier.weight(1f),
                )
                ChargeStat(
                    formatPower(session.peakPowerKW, units),
                    stringResource(R.string.charging_stat_peak),
                    Modifier.weight(1f),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ChargeStat(
                    formatPower(session.averagePowerKW, units),
                    stringResource(R.string.charging_average_power),
                    Modifier.weight(1f),
                )
                ChargeStat(
                    formatElapsed(session.duration.seconds.toDouble()),
                    stringResource(R.string.charging_stat_duration),
                    Modifier.weight(1f),
                )
                if (pricePerKWh > 0) {
                    ChargeStat(
                        NumberFormat.getCurrencyInstance().format(session.totalKWhDelivered * pricePerKWh),
                        stringResource(R.string.charging_stat_cost),
                        Modifier.weight(1f),
                    )
                } else {
                    Spacer(Modifier.weight(1f))
                }
            }

            Text(
                stringResource(R.string.charging_detail_location),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
            Text(session.locationName, color = Theme.textPrimary, fontSize = 13.sp)
            val latitude = session.latitude
            val longitude = session.longitude
            Text(
                if (session.hasLocation && latitude != null && longitude != null) {
                    stringResource(R.string.charging_detail_coordinates, latitude, longitude)
                } else {
                    stringResource(R.string.charging_detail_no_location)
                },
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )

            val startTemp = session.startBatteryTempC
            val endTemp = session.endBatteryTempC
            if (startTemp != null || endTemp != null) {
                Text(
                    stringResource(R.string.charging_detail_temperature),
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
                Text(
                    stringResource(
                        R.string.charging_detail_temp_range,
                        startTemp?.let { formatTemperature(it, units) } ?: "—",
                        endTemp?.let { formatTemperature(it, units) } ?: "—",
                    ),
                    color = Theme.textPrimary,
                    fontSize = 13.sp,
                )
            }

            val startRange = session.startRangeKm
            val endRange = session.endRangeKm
            if (startRange != null || endRange != null) {
                Text(
                    stringResource(R.string.charging_detail_range),
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
                Text(
                    stringResource(
                        R.string.charging_detail_temp_range,
                        startRange?.let { formatDistance(it, units) } ?: "—",
                        endRange?.let { formatDistance(it, units) } ?: "—",
                    ),
                    color = Theme.textPrimary,
                    fontSize = 13.sp,
                )
            }

            val points = ChargingSpeedCurve.session(session.samples)
            if (points.size >= 2) {
                ChargingSpeedChart(points = points, units = units)
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(
                    onClick = {
                        scope.launch {
                            ExportShare.share(
                                context = context,
                                fileName = TripExport.chargingFilename(session, "csv"),
                                mimeType = ExportShare.csvMimeType,
                                content = TripExport.chargingCsv(session),
                            )
                        }
                    },
                    contentPadding = PaddingValues(0.dp),
                ) {
                    Text(
                        stringResource(R.string.charging_share_csv),
                        color = Theme.electricCyan,
                        fontSize = 12.sp,
                    )
                }
                Spacer(Modifier.weight(1f))
                TextButton(
                    onClick = { confirmDelete = true },
                    contentPadding = PaddingValues(0.dp),
                ) {
                    Text(
                        stringResource(R.string.charging_detail_delete),
                        color = Theme.criticalRed,
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.charging_delete_title)) },
            text = { Text(stringResource(R.string.charging_delete_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDelete = false
                        onDelete()
                    },
                ) {
                    Text(stringResource(R.string.charging_delete_confirm), color = Theme.criticalRed)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) {
                    Text(stringResource(R.string.charging_cancel))
                }
            },
        )
    }
}

@Composable
private fun BatteryHealthCard(health: List<BatteryHealthRecord>) {
    val first = health.first()
    val latest = health.last()
    val change = latest.sohPct - first.sohPct
    val days = Duration.between(first.timestamp, latest.timestamp).toDays().coerceAtLeast(1)
    val projection = if (health.size >= 14 && days >= 14) (change / days) * 365.0 else null

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.battery_health_title),
                color = Theme.textPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Text(
                stringResource(R.string.battery_health_soh, latest.sohPct),
                color = Theme.regenGreen,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Canvas(modifier = Modifier.fillMaxWidth().height(90.dp)) {
            val minSoh = (health.minOf { it.sohPct } - 1.0)
            val maxSoh = (health.maxOf { it.sohPct } + 1.0)
            val span = (maxSoh - minSoh).coerceAtLeast(1.0)
            val stepX = size.width / (health.size - 1).coerceAtLeast(1)
            val path = Path()
            health.forEachIndexed { index, reading ->
                val x = index * stepX
                val y = (size.height - ((reading.sohPct - minSoh) / span) * size.height).toFloat()
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, Theme.regenGreen, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
        }
        Row {
            Text(
                stringResource(R.string.battery_health_change, change),
                color = if (change < 0) Theme.highPowerAmber else Theme.textSecondary,
                fontSize = 11.sp,
                modifier = Modifier.weight(1f),
            )
            Text(
                stringResource(R.string.battery_health_readings, health.size),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
        if (projection != null) {
            Text(
                stringResource(R.string.battery_health_projection, projection),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
    }
}

