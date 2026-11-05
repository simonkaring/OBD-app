package com.simonkaring.voltlink.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.VoltLinkApplication
import com.simonkaring.voltlink.core.demo.DemoProfile
import com.simonkaring.voltlink.core.demo.DemoScenario
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import java.util.Locale

/** Standalone development activity, NOT an Android Auto custom-layout surface. */
class CompanionPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as VoltLinkApplication
        setContent {
            var state by remember { mutableStateOf(readState(app)) }
            LaunchedEffect(app) {
                lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    // A clock also expires readings when the upstream flow stops emitting.
                    while (isActive) {
                        state = readState(app)
                        delay(1_000)
                    }
                }
            }
            CompanionPreview(state, onScenario = { scenario ->
                val manager = app.vehicleData
                if (!manager.isDemoMode.value && !manager.connectionState.value.isConnected) {
                    manager.setDemoMode(true)
                }
                if (manager.isDemoMode.value) manager.simulation.scenario = scenario
            })
        }
    }
}

internal fun readState(app: VoltLinkApplication): CompanionState {
    val manager = app.vehicleData
    val demo = manager.isDemoMode.value
    val profile = if (demo) DemoProfile() else manager.selectedProfile
    return companionState(
        snapshot = manager.telemetry.value, liveMetrics = manager.liveMetrics.value,
        supportedMetrics = profile.supportedMetrics, connection = manager.connectionState.value,
        demo = demo, capacityKWh = profile.batteryUsableCapacityKWh,
        trip = app.tripTracker.state.value, charging = app.chargingTracker.state.value,
        priceDKKPerKWh = manager.settings.tripCostPerKWh.value,
    )
}

@Composable
internal fun CompanionPreview(state: CompanionState, onScenario: (DemoScenario) -> Unit) {
    var page by rememberSaveable { mutableIntStateOf(0) }
    var dark by rememberSaveable { mutableStateOf<Boolean?>(null) }
    val night = dark ?: isSystemInDarkTheme()
    val colors = if (night) darkColorScheme(
        primary = Color(0xFF91E5C2), background = Color(0xFF101715), surface = Color(0xFF1B2722),
        secondaryContainer = Color(0xFF284C3D), onSecondaryContainer = Color(0xFF91E5C2),
    ) else lightColorScheme(
        primary = Color(0xFF006C4C), background = Color(0xFFF2F7F4), surface = Color(0xFFE1ECE5),
        secondaryContainer = Color(0xFFC3EAD9), onSecondaryContainer = Color(0xFF004D35),
    )
    MaterialTheme(colorScheme = colors) {
        Surface(Modifier.fillMaxSize(), color = colors.background) {
            Column(Modifier.safeDrawingPadding().padding(horizontal = 24.dp, vertical = 8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.companion_preview), fontWeight = FontWeight.Bold, fontSize = 22.sp)
                        Text(stringResource(R.string.companion_not_auto), style = MaterialTheme.typography.labelLarge)
                    }
                    TextButton(onClick = { dark = !night }, modifier = Modifier.heightIn(min = 48.dp)) {
                        Text(stringResource(if (night) R.string.companion_day else R.string.companion_night))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    listOf(R.string.companion_drive, R.string.companion_charging, R.string.companion_vehicle).forEachIndexed { index, label ->
                        FilterChip(selected = page == index, onClick = { page = index },
                            label = { Text(stringResource(label), fontSize = 18.sp) }, modifier = Modifier.heightIn(min = 48.dp))
                    }
                }
                Text(stringResource(when (state.connection) {
                    CompanionConnection.DISCONNECTED -> R.string.companion_disconnected
                    CompanionConnection.CONNECTING -> R.string.companion_connecting
                    CompanionConnection.STALE -> R.string.companion_stale
                    CompanionConnection.LIVE -> R.string.companion_live
                    CompanionConnection.DEMO -> R.string.companion_demo
                }), color = colors.primary, style = MaterialTheme.typography.bodyLarge)
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    when (page) {
                        0 -> DriveOverview(state)
                        1 -> ChargingOverview(state)
                        else -> VehicleOverview(state)
                    }
                    if (state.connection == CompanionConnection.DISCONNECTED || state.connection == CompanionConnection.DEMO) {
                        Text(stringResource(R.string.companion_simulation), style = MaterialTheme.typography.labelLarge)
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            listOf(
                                R.string.companion_city to DemoScenario.CITY_DRIVING,
                                R.string.companion_highway to DemoScenario.HIGHWAY_CRUISING,
                                R.string.companion_charge to DemoScenario.DC_FAST_CHARGING,
                            ).forEach { (label, scenario) ->
                                OutlinedButton(onClick = { onScenario(scenario) }, modifier = Modifier.heightIn(min = 48.dp)) {
                                    Text(stringResource(label))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DriveOverview(state: CompanionState) {
    MetricRow(listOf(
        R.string.companion_soc to number(state.metrics[TelemetryMetric.SOC], 0, "%"),
        R.string.companion_range to number(state.rangeKm, 0, "km", state.rangeEstimated),
        R.string.companion_speed to number(state.metrics[TelemetryMetric.SPEED], 0, "km/h"),
    ), prominent = true)
    val power = state.metrics[TelemetryMetric.POWER]
    MetricRow(listOf(
        (if (power != null && power < 0 && state.charging != CompanionCharging.ACTIVE) R.string.companion_regen else R.string.companion_power) to number(power, 1, "kW"),
        R.string.companion_consumption to number(state.tripConsumption, 1, "kWh/100 km"),
    ))
    MetricRow(listOf(
        R.string.companion_distance to number(state.tripDistanceKm, 1, "km"),
        R.string.companion_duration to clock(state.tripSeconds),
    ))
}

@Composable
private fun ChargingOverview(state: CompanionState) {
    Text(stringResource(when (state.charging) {
        CompanionCharging.DISCONNECTED -> R.string.companion_disconnected
        CompanionCharging.UNAVAILABLE -> R.string.companion_charge_unknown
        CompanionCharging.INACTIVE -> R.string.companion_inactive
        CompanionCharging.ACTIVE -> R.string.companion_active
        CompanionCharging.COMPLETE -> R.string.companion_complete
    }), style = MaterialTheme.typography.titleLarge)
    MetricRow(listOf(
        R.string.companion_soc to number(state.metrics[TelemetryMetric.SOC], 0, "%"),
        R.string.companion_charge_power to number(state.chargePowerKW, 1, "kW", state.chargePowerEstimated),
        R.string.companion_to80 to (state.secondsTo80?.let { number(kotlin.math.ceil(it / 60), 0, "min", true) } ?: "—"),
    ), prominent = true)
    MetricRow(listOf(
        R.string.companion_energy to number(state.energyAddedKWh, 2, "kWh"),
        R.string.companion_duration to clock(state.chargingSeconds),
        R.string.companion_cost to number(state.costDKK, 2, "DKK", true),
    ))
}

@Composable
private fun VehicleOverview(state: CompanionState) {
    val requested = listOf(TelemetryMetric.SOC, TelemetryMetric.PACK_VOLTAGE, TelemetryMetric.BATTERY_TEMP,
        TelemetryMetric.POWER, TelemetryMetric.SOH)
    requested.filter { it in state.metrics }.forEach { metric ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(metric.displayName, fontSize = 22.sp)
            Text(number(state.metrics[metric], metric.decimalPlaces, metric.unitSymbol), fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        }
    }
    MetricRow(listOf(
        R.string.companion_consumption to number(state.tripConsumption, 1, "kWh/100 km"),
        R.string.companion_capacity to number(state.capacityKWh, 1, "kWh"),
    ))
    Text(stringResource(R.string.companion_details_note), style = MaterialTheme.typography.bodyLarge)
}

@Composable
private fun MetricRow(values: List<Pair<Int, String>>, prominent: Boolean = false) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        values.forEach { (label, value) ->
            Column(Modifier.weight(1f)) {
                Text(stringResource(label), style = MaterialTheme.typography.bodyLarge)
                Text(value, fontSize = (if (prominent) 36 else 24).sp, fontWeight = FontWeight.SemiBold,
                    color = if (prominent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onBackground)
            }
        }
    }
}

internal fun number(value: Double?, decimals: Int, unit: String, estimate: Boolean = false): String =
    value?.takeIf { it.isFinite() }?.let {
        (if (estimate) "≈ " else "") + String.format(Locale.getDefault(), "%.${decimals}f %s", it, unit)
    } ?: "—"

internal fun clock(seconds: Long?): String = seconds?.let {
    String.format(Locale.getDefault(), "%d:%02d:%02d", it / 3600, it % 3600 / 60, it % 60)
} ?: "—"
