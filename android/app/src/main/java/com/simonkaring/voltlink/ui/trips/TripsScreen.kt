package com.simonkaring.voltlink.ui.trips

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Route
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.export.ExportShare
import com.simonkaring.voltlink.core.export.TripExport
import com.simonkaring.voltlink.core.history.TripHistoryInsights
import com.simonkaring.voltlink.data.DistanceUnit
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import com.simonkaring.voltlink.services.TripLocationService
import com.simonkaring.voltlink.services.TripTracker
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.components.EmptyState
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val dateFormatter = DateTimeFormatter.ofPattern("EEE d MMM · HH:mm").withZone(ZoneId.systemDefault())

/** Trip log with start/stop control, per-trip stats and the recorded SOC/power curve. */
@Composable
fun TripsScreen(
    manager: VehicleDataManager,
    tracker: TripTracker,
    units: UnitPrefs,
    modifier: Modifier = Modifier,
) {
    val state by tracker.state.collectAsStateWithLifecycle()
    val trips by tracker.history.collectAsStateWithLifecycle()
    val snapshot by manager.telemetry.collectAsStateWithLifecycle()
    var selectedTrip by remember { mutableStateOf<TripRecord?>(null) }
    val context = LocalContext.current
    val pricePerKWh by manager.settings.tripCostPerKWh.collectAsStateWithLifecycle()
    // Completed trips of the current calendar month, priced with the settings' electricity rate.
    val monthlyInsights = remember(trips, pricePerKWh) {
        TripHistoryInsights.summarize(
            trips = trips,
            since = TripHistoryInsights.startOfMonth(),
            pricePerKWh = pricePerKWh,
        )
    }

    selectedTrip?.let { trip ->
        TripDetail(
            trip = trip,
            tracker = tracker,
            units = units,
            onBack = { selectedTrip = null },
            onDelete = {
                tracker.deleteTrip(trip.id)
                selectedTrip = null
            },
        )
        return
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
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(9.dp).clip(CircleShape).background(
                        if (state.isRecording) Theme.regenGreen else Theme.textSecondary,
                    ))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = if (state.isRecording) {
                            stringResource(R.string.trips_recording)
                        } else {
                            stringResource(R.string.trips_ready)
                        },
                        color = if (state.isRecording) Theme.regenGreen else Theme.textSecondary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (state.isAutoTripEnabled) {
                        Spacer(Modifier.width(8.dp))
                        Text(
                            stringResource(R.string.trips_auto),
                            color = Theme.electricCyan,
                            fontSize = 10.sp,
                            modifier = Modifier
                                .background(Theme.electricCyan.copy(alpha = 0.2f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 5.dp, vertical = 2.dp),
                        )
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = if (state.isRecording) {
                            String.format(Locale.US, "%d:%02d", state.current?.duration?.toMinutes() ?: 0, (state.current?.duration?.seconds ?: 0) % 60)
                        } else {
                            ""
                        },
                        color = Theme.textSecondary,
                        fontSize = 12.sp,
                    )
                }
                Text(
                    text = stringResource(
                        R.string.trips_logged,
                        state.current?.distanceKm?.let {
                            if (units.distanceLabel() == "mi") it * 0.621371 else it
                        } ?: 0.0,
                        units.distanceLabel(),
                    ),
                    color = Theme.textPrimary,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                val stationarySeconds = state.stationarySecondsRemaining
                if (stationarySeconds != null) {
                    Text(
                        stringResource(R.string.trips_stationary, stationarySeconds),
                        color = Theme.highPowerAmber,
                        fontSize = 12.sp,
                    )
                }
                val locationPermission = rememberLauncherForActivityResult(
                    ActivityResultContracts.RequestPermission(),
                ) { granted ->
                    // Granted mid-recording: the application observer only starts on the next
                    // state change, so start directly here.
                    if (granted && tracker.state.value.isRecording) TripLocationService.start(context)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = {
                            if (state.isRecording) {
                                tracker.stop(snapshot.stateOfChargePct)
                            } else {
                                tracker.start(snapshot.stateOfChargePct, manager.vehicleDisplayName)
                                // Asked from this user action only: no location permission at launch.
                                if (!TripLocationService.hasLocationPermission(context)) {
                                    locationPermission.launch(android.Manifest.permission.ACCESS_FINE_LOCATION)
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (state.isRecording) Theme.criticalRed else Theme.electricCyan,
                        ),
                    ) {
                        Text(
                            if (state.isRecording) stringResource(R.string.trips_stop) else stringResource(R.string.trips_start),
                            color = Theme.onAccent,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    TextButton(onClick = { tracker.setAutoTrips(!state.isAutoTripEnabled) }) {
                        Text(
                            if (state.isAutoTripEnabled) {
                                stringResource(R.string.trips_disable_auto)
                            } else {
                                stringResource(R.string.trips_enable_auto)
                            },
                            color = Theme.textSecondary,
                        )
                    }
                }
                state.error?.let { Text(it, color = Theme.highPowerAmber, fontSize = 11.sp) }
            }
        }

        if (monthlyInsights.tripCount > 0) {
            item { MonthlySummaryCard(monthlyInsights, units) }
        }

        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Route, contentDescription = null, tint = Theme.textSecondary, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.trips_history), color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                Text(
                    if (trips.size == 1) stringResource(R.string.trips_count_one) else stringResource(R.string.trips_count_many, trips.size),
                    color = Theme.textSecondary,
                    fontSize = 12.sp,
                )
            }
        }

        if (trips.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Filled.Route,
                    title = stringResource(R.string.trips_empty_title),
                    message = stringResource(R.string.trips_empty),
                )
            }
        }

        items(trips, key = { it.id }) { trip ->
            TripCard(trip = trip, units = units) { selectedTrip = trip }
        }
    }
}

private fun UnitPrefs.distanceLabel(): String = if (distance == DistanceUnit.MILES) "mi" else "km"

/** This month's completed-trip totals: distance, net energy, weighted efficiency and cost. */
@Composable
private fun MonthlySummaryCard(insights: TripHistoryInsights, units: UnitPrefs) {
    val miles = units.distance == DistanceUnit.MILES
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.trips_month), color = Theme.electricCyan, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text(
                if (insights.tripCount == 1) {
                    stringResource(R.string.trips_count_one)
                } else {
                    stringResource(R.string.trips_count_many, insights.tripCount)
                },
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
        Row(modifier = Modifier.fillMaxWidth()) {
            InsightStat(
                String.format(
                    Locale.US,
                    "%.1f %s",
                    if (miles) insights.distanceKm * 0.621371 else insights.distanceKm,
                    units.distanceLabel(),
                ),
                stringResource(R.string.trips_stat_distance),
            )
            InsightStat(
                String.format(Locale.US, "%.1f kWh", insights.energyKWh),
                stringResource(R.string.trips_stat_energy),
            )
            InsightStat(
                String.format(Locale.US, "%.1f kWh/100km", insights.efficiencyKWhPer100Km),
                stringResource(R.string.trips_stat_efficiency),
            )
            if (insights.hasCost) {
                InsightStat(
                    NumberFormat.getCurrencyInstance().format(insights.cost),
                    stringResource(R.string.trips_stat_cost),
                )
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.InsightStat(value: String, label: String) {
    Column(Modifier.weight(1f)) {
        Text(
            value,
            color = Theme.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            softWrap = false,
        )
        Text(label, color = Theme.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun TripCard(trip: TripRecord, units: UnitPrefs, onClick: () -> Unit) {
    val distance = if (units.distance == com.simonkaring.voltlink.data.DistanceUnit.MILES) trip.distanceKm * 0.621371 else trip.distanceKm
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(dateFormatter.format(trip.startTime), color = Theme.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
            if (trip.endTime == null) {
                Text("REC", color = Theme.regenGreen, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }
        Text(trip.vehicleName, color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Stat(
                String.format(Locale.US, "%.1f %s", distance, units.distanceLabel()),
                stringResource(R.string.trips_stat_distance),
            )
            Stat(
                String.format(Locale.US, "%.1f kWh/100km", trip.efficiencyKWhPer100Km),
                stringResource(R.string.trips_stat_efficiency),
            )
            Stat(
                String.format(Locale.US, "%.0f%% → %.0f%%", trip.startSocPct, trip.endSocPct),
                stringResource(R.string.trips_stat_soc),
            )
        }
    }
}

@Composable
private fun Stat(value: String, label: String) {
    Column {
        Text(value, color = Theme.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        Text(label, color = Theme.textSecondary, fontSize = 10.sp)
    }
}

@Composable
private fun TripDetail(
    trip: TripRecord,
    tracker: TripTracker,
    units: UnitPrefs,
    onBack: () -> Unit,
    onDelete: () -> Unit,
) {
    var samples by remember(trip.id) { mutableStateOf<List<TripSample>>(emptyList()) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    LaunchedEffect(trip.id) {
        samples = trip.samples.ifEmpty { tracker.loadSamples(trip.id) }
    }
    val distance = if (units.distance == com.simonkaring.voltlink.data.DistanceUnit.MILES) trip.distanceKm * 0.621371 else trip.distanceKm

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) {
                Icon(
                    Icons.Filled.ArrowBack,
                    contentDescription = stringResource(R.string.trips_back),
                    tint = Theme.electricCyan,
                )
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.trips_title), color = Theme.electricCyan)
            }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { scope.launch { onDelete() } }) {
                Text(stringResource(R.string.trips_delete), color = Theme.criticalRed)
            }
        }
        Text(dateFormatter.format(trip.startTime), color = Theme.textSecondary, fontSize = 12.sp)
        Text(trip.vehicleName, color = Theme.textPrimary, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(Theme.cardBackground)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat(
                    String.format(Locale.US, "%.1f %s", distance, units.distanceLabel()),
                    stringResource(R.string.trips_stat_distance),
                )
                Stat(
                    String.format(Locale.US, "%d min", trip.duration.toMinutes()),
                    stringResource(R.string.trips_stat_duration),
                )
                Stat(
                    String.format(Locale.US, "%.0f %s", units.speedValue(trip.computedAverageSpeedKmH), units.speedUnit),
                    stringResource(R.string.trips_stat_avg_speed),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat(
                    String.format(Locale.US, "%.1f kWh", trip.totalKWhUsed),
                    stringResource(R.string.trips_stat_energy_used),
                )
                Stat(
                    String.format(Locale.US, "%.1f kWh", trip.totalKWhRecovered ?: 0.0),
                    stringResource(R.string.trips_stat_recovered),
                )
                Stat(
                    String.format(Locale.US, "%.0f kW", trip.maxPowerKW),
                    stringResource(R.string.trips_stat_peak_power),
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Stat(
                    String.format(Locale.US, "%.1f kWh/100km", trip.efficiencyKWhPer100Km),
                    stringResource(R.string.trips_stat_efficiency),
                )
                Stat(
                    String.format(Locale.US, "%.0f%% → %.0f%%", trip.startSocPct, trip.endSocPct),
                    stringResource(R.string.trips_stat_state_of_charge),
                )
            }
        }

        // Same exports as the iOS trip detail: the raw sample table as CSV and the recorded
        // route as GPX. The GPX action only appears once a position fix was captured.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (TripExport.hasRoute(samples)) {
                Button(
                    onClick = {
                        scope.launch {
                            ExportShare.share(
                                context = context,
                                fileName = TripExport.tripFilename(trip, "gpx"),
                                mimeType = ExportShare.gpxMimeType,
                                content = TripExport.gpx(trip, samples),
                            )
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = Theme.subtleFill),
                ) {
                    Text(stringResource(R.string.trips_share_gpx), color = Theme.textPrimary, fontSize = 13.sp)
                }
            }
            Button(
                onClick = {
                    scope.launch {
                        ExportShare.share(
                            context = context,
                            fileName = TripExport.tripFilename(trip, "csv"),
                            mimeType = ExportShare.csvMimeType,
                            content = TripExport.csv(trip, samples),
                        )
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = Theme.subtleFill),
            ) {
                Text(stringResource(R.string.trips_share_csv), color = Theme.textPrimary, fontSize = 13.sp)
            }
        }

        if (samples.size >= 2) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Theme.cardBackground)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.trips_recorded),
                    color = Theme.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                SampleChart(samples)
            }
        }
    }
}

/** Dual-series SOC and power trace for a recorded trip. */
@Composable
private fun SampleChart(samples: List<TripSample>) {
    Canvas(modifier = Modifier.fillMaxWidth().height(160.dp)) {
        repeat(4) { index ->
            val y = size.height * index / 3f
            drawLine(Theme.chartGrid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
        }
        fun path(values: List<Double>, maxValue: Double, invert: Boolean): Path {
            val path = Path()
            val stepX = size.width / (values.size - 1).coerceAtLeast(1)
            values.forEachIndexed { index, value ->
                val fraction = if (invert) {
                    0.5 - (value / maxValue) * 0.45
                } else {
                    0.95 - (value / maxValue) * 0.9
                }
                val point = Offset(index * stepX, (fraction * size.height).toFloat())
                if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
            }
            return path
        }
        val maxPower = maxOf(1.0, samples.maxOfOrNull { kotlin.math.abs(it.powerKW) } ?: 1.0)
        val maxSpeed = maxOf(1.0, samples.maxOfOrNull { it.speedKmH } ?: 1.0)
        drawPath(path(samples.map { it.powerKW }, maxPower, true), Theme.gaugeCyan, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
        drawPath(path(samples.map { it.speedKmH }, maxSpeed, false), Theme.regenGreen, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
    }
    Row {
        Text(stringResource(R.string.chart_series_power), color = Theme.gaugeCyan, fontSize = 11.sp)
        Spacer(Modifier.width(12.dp))
        Text(stringResource(R.string.chart_series_speed), color = Theme.regenGreen, fontSize = 11.sp)
    }
}
