package com.simonkaring.voltlink.ui.charging

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.core.export.ExportShare
import com.simonkaring.voltlink.core.export.TripExport
import com.simonkaring.voltlink.core.telemetry.ChargingTimeEstimator
import com.simonkaring.voltlink.data.BatteryHealthRecord
import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.HistoryStore
import com.simonkaring.voltlink.services.ChargingTracker
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val sessionDateFormatter = DateTimeFormatter.ofPattern("d MMM HH:mm").withZone(ZoneId.systemDefault())

/** Charging tab: live session with time-to-target, session history and battery health. */
@Composable
fun ChargingScreen(
    manager: VehicleDataManager,
    tracker: ChargingTracker,
    store: HistoryStore,
    modifier: Modifier = Modifier,
) {
    val state by tracker.state.collectAsStateWithLifecycle()
    val sessions by tracker.history.collectAsStateWithLifecycle()
    val health by store.batteryHealth.collectAsStateWithLifecycle()
    val snapshot by manager.telemetry.collectAsStateWithLifecycle()
    val target by manager.settings.chargeTargetPercent.collectAsStateWithLifecycle()

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
                        imageVector = if (state.isCharging) Icons.Filled.Bolt else Icons.Filled.BatteryChargingFull,
                        contentDescription = null,
                        tint = if (state.isCharging) Theme.regenGreen else Theme.textSecondary,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = if (state.isCharging) "Charging" else "Not charging",
                        color = Theme.textPrimary,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f),
                    )
                    Text("target $target%", color = Theme.textSecondary, fontSize = 12.sp)
                }

                Text(
                    text = String.format(Locale.US, "%.0f%%", snapshot.stateOfChargePct),
                    color = if (snapshot.stateOfChargePct < 20) Theme.criticalRed else Theme.regenGreen,
                    fontSize = 40.sp,
                    fontWeight = FontWeight.Bold,
                )

                // SOC bar with a target marker drawn on the fill. Drawn in one Canvas so
                // the tick cannot stretch into a filled block of its own.
                Canvas(modifier = Modifier.fillMaxWidth().height(14.dp)) {
                    val radius = size.height / 2
                    drawRoundRect(
                        color = Theme.trackBackground,
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius, radius),
                    )
                    val fraction = (snapshot.stateOfChargePct.coerceIn(0.0, 100.0) / 100.0).toFloat()
                    if (fraction > 0f) {
                        drawRoundRect(
                            color = if (snapshot.isCharging) Theme.regenGreen else Theme.gaugeCyan,
                            size = androidx.compose.ui.geometry.Size(size.width * fraction, size.height),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius, radius),
                        )
                    }
                    val targetX = size.width * (target.coerceIn(0, 100) / 100f)
                    drawRect(
                        color = Theme.textPrimary,
                        topLeft = Offset(targetX - 1.dp.toPx(), 0f),
                        size = androidx.compose.ui.geometry.Size(2.dp.toPx(), size.height),
                    )
                }

                Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                    ChargeStat(
                        String.format(Locale.US, "%.1f kW", snapshot.chargePowerKW),
                        if (snapshot.chargePowerKW > ChargingTimeEstimator.DC_POWER_THRESHOLD_KW) "DC power" else "power",
                    )
                    ChargeStat(
                        when {
                            state.secondsToTarget == null -> "—"
                            state.secondsToTarget == 0.0 -> "Reached"
                            else -> formatDuration(state.secondsToTarget!!)
                        },
                        "to $target%",
                    )
                    ChargeStat(
                        String.format(Locale.US, "%.1f kWh", state.current?.totalKWhDelivered ?: 0.0),
                        "delivered",
                    )
                }
                if (state.isCharging && state.secondsToTarget == null) {
                    Text(
                        "Time to target needs a live charge-power reading.",
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }
            }
        }

        if (health.size >= 2) {
            item { BatteryHealthCard(health) }
        }

        item {
            Text(
                "Charging history",
                color = Theme.textPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }

        if (sessions.isEmpty()) {
            item {
                Text(
                    "No charging sessions recorded yet. A session is saved once the vehicle reports charging for more than 90 seconds.",
                    color = Theme.textSecondary,
                    fontSize = 13.sp,
                )
            }
        }

        items(sessions, key = { it.id }) { session ->
            SessionCard(session)
        }
    }
}

@Composable
private fun ChargeStat(value: String, label: String) {
    Column {
        Text(value, color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Text(label, color = Theme.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun SessionCard(session: ChargingSessionRecord) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row {
            Text(sessionDateFormatter.format(session.startTime), color = Theme.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
            Text(session.locationName, color = Theme.textSecondary, fontSize = 11.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            ChargeStat(
                String.format(Locale.US, "%.0f%% → %.0f%%", session.startSocPct, session.endSocPct),
                "state of charge",
            )
            ChargeStat(String.format(Locale.US, "%.1f kWh", session.totalKWhDelivered), "delivered")
            ChargeStat(String.format(Locale.US, "%.0f kW", session.peakPowerKW), "peak")
            ChargeStat(formatDuration(session.duration.seconds.toDouble()), "duration")
        }
        if (session.samples.size >= 2) {
            // Charge curve: power against SoC.
            Canvas(modifier = Modifier.fillMaxWidth().height(70.dp)) {
                val maxPower = maxOf(1.0, session.samples.maxOf { it.powerKW })
                val sorted = session.samples.sortedBy { it.socPct }
                val path = Path()
                sorted.forEachIndexed { index, sample ->
                    val x = (sample.socPct / 100.0 * size.width).toFloat()
                    val y = (size.height - (sample.powerKW / maxPower) * size.height).toFloat()
                    if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(path, Theme.gaugeCyan, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
                drawLine(
                    Theme.chartGrid,
                    Offset(0f, size.height - 1f),
                    Offset(size.width, size.height - 1f),
                    strokeWidth = 1f,
                )
            }
            Text("Charging speed over state of charge", color = Theme.textSecondary, fontSize = 10.sp)
        }
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
            Text("Share CSV", color = Theme.electricCyan, fontSize = 12.sp)
        }
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
            Text("Battery health", color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(
                String.format(Locale.US, "%.1f%% SOH", latest.sohPct),
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
                String.format(Locale.US, "%+.1f%% since first reading", change),
                color = if (change < 0) Theme.highPowerAmber else Theme.textSecondary,
                fontSize = 11.sp,
                modifier = Modifier.weight(1f),
            )
            Text("${health.size} daily readings", color = Theme.textSecondary, fontSize = 11.sp)
        }
        if (projection != null) {
            Text(
                String.format(Locale.US, "Projected %.1f%% per year", projection),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
    }
}

private fun formatDuration(seconds: Double): String {
    if (!seconds.isFinite() || seconds <= 0) return "—"
    val totalMinutes = (seconds / 60).toInt()
    val hours = totalMinutes / 60
    val minutes = totalMinutes % 60
    return if (hours > 0) "${hours} h ${minutes} min" else "$minutes min"
}
