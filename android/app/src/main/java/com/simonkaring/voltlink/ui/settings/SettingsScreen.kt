package com.simonkaring.voltlink.ui.settings

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.core.export.ExportShare
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.vehicles.CommunityContributionBuilder
import com.simonkaring.voltlink.core.widget.TelemetryWidgetProvider
import com.simonkaring.voltlink.core.vehicles.ServiceReminderMonitor
import com.simonkaring.voltlink.core.vehicles.VehicleProfileId
import com.simonkaring.voltlink.data.DistanceUnit
import com.simonkaring.voltlink.data.PowerUnit
import com.simonkaring.voltlink.data.TemperatureUnit
import com.simonkaring.voltlink.services.BleDeviceInfo
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.launch
import java.util.Locale

/** Settings: simulation, adapter pairing, vehicle profile, units and charging target. */
@Composable
fun SettingsScreen(
    manager: VehicleDataManager,
    serviceReminder: ServiceReminderMonitor,
    historyStore: com.simonkaring.voltlink.data.HistoryStore,
    modifier: Modifier = Modifier,
) {
    val settings = manager.settings
    val isDemoMode by manager.isDemoMode.collectAsStateWithLifecycle()
    val connectionState by manager.connectionState.collectAsStateWithLifecycle()
    val devices by manager.discoveredDevices.collectAsStateWithLifecycle()
    val profileId by manager.selectedProfileId.collectAsStateWithLifecycle()
    val log by manager.obdLog.collectAsStateWithLifecycle()
    val distanceUnit by settings.distanceUnit.collectAsStateWithLifecycle()
    val temperatureUnit by settings.temperatureUnit.collectAsStateWithLifecycle()
    val powerUnit by settings.powerUnit.collectAsStateWithLifecycle()
    val chargeTarget by settings.chargeTargetPercent.collectAsStateWithLifecycle()
    val tripCostPerKWh by settings.tripCostPerKWh.collectAsStateWithLifecycle()
    val notificationsEnabled by settings.notificationsEnabled.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    var showProfiles by remember { mutableStateOf(false) }
    var showCatalog by remember { mutableStateOf(false) }
    var showLog by remember { mutableStateOf(false) }
    var showMetricStatus by remember { mutableStateOf(false) }
    var showCarLayout by remember { mutableStateOf(false) }
    val selectedModelName by settings.selectedModelName.collectAsStateWithLifecycle()
    val liveMetrics by manager.liveMetrics.collectAsStateWithLifecycle()
    val carLayout by settings.carTileLayout.collectAsStateWithLifecycle()

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 8.dp, bottom = 24.dp),
    ) {
        item {
            SettingsCard("Connection") {
                ToggleRow(
                    title = "Demo / Simulation mode",
                    subtitle = "Stream simulated telemetry without an adapter",
                    checked = isDemoMode,
                    onCheckedChange = { manager.setDemoMode(it) },
                )
                SettingDivider()
                Text(
                    text = when (val state = connectionState) {
                        is BleConnectionState.Ready -> "Connected to ${state.deviceName}"
                        is BleConnectionState.Connecting -> "Connecting to ${state.deviceName}…"
                        is BleConnectionState.Error -> state.message
                        BleConnectionState.Scanning -> "Scanning for adapters…"
                        BleConnectionState.DemoMode -> "Demo mode active"
                        BleConnectionState.Disconnected -> "No adapter connected"
                    },
                    color = Theme.textSecondary,
                    fontSize = 12.sp,
                )
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { manager.startScan() },
                        colors = ButtonDefaults.buttonColors(containerColor = Theme.electricCyan),
                    ) {
                        Text(
                            if (connectionState is BleConnectionState.Scanning) "Scanning…" else "Scan for adapters",
                            color = Theme.onAccent,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    TextButton(onClick = { manager.disconnect() }) {
                        Text("Disconnect", color = Theme.textSecondary)
                    }
                }
                if (devices.isNotEmpty() && !isDemoMode) {
                    Spacer(Modifier.height(4.dp))
                    devices.forEach { device -> DeviceRow(device) { manager.connectToAdapter(device.address) } }
                }
            }
        }

        item {
            SettingsCard("Vehicle") {
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { showProfiles = !showProfiles },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            selectedModelName ?: manager.selectedProfile.vehicleName,
                            color = Theme.textPrimary,
                            fontSize = 14.sp,
                        )
                        Text(
                            if (selectedModelName != null) {
                                "${manager.selectedProfile.vehicleName} · " +
                                    "${manager.selectedProfile.supportedMetrics.size} published metrics"
                            } else {
                                "${manager.selectedProfile.supportedMetrics.size} published metrics"
                            },
                            color = Theme.textSecondary,
                            fontSize = 12.sp,
                        )
                    }
                    Text(if (showProfiles) "Close" else "Change", color = Theme.electricCyan, fontSize = 13.sp)
                }
                Row {
                    TextButton(onClick = { showCatalog = true }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                        Text("Browse vehicle catalog", color = Theme.electricCyan, fontSize = 13.sp)
                    }
                    Spacer(Modifier.width(12.dp))
                    TextButton(
                        onClick = { showMetricStatus = true },
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                    ) {
                        Text("Metric status", color = Theme.electricCyan, fontSize = 13.sp)
                    }
                }
                if (showProfiles) {
                    Spacer(Modifier.height(8.dp))
                    VehicleProfileId.entries.forEach { id ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(if (id == profileId) Theme.electricCyan.copy(alpha = 0.15f) else Theme.faintFill)
                                .clickable {
                                    manager.selectProfile(id)
                                    showProfiles = false
                                }
                                .padding(horizontal = 10.dp, vertical = 10.dp),
                        ) {
                            Text(
                                id.displayName,
                                color = if (id == profileId) Theme.electricCyan else Theme.textPrimary,
                                fontSize = 13.sp,
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                    }
                }
            }
        }

        item {
            SettingsCard("Units") {
                Text("Distance & speed", color = Theme.textSecondary, fontSize = 12.sp)
                SegmentedRow(
                    options = DistanceUnit.entries.map { it.name to it.label },
                    selected = distanceUnit.name,
                    onSelect = { name -> settings.setDistanceUnit(DistanceUnit.valueOf(name)) },
                )
                Spacer(Modifier.height(10.dp))
                Text("Temperature", color = Theme.textSecondary, fontSize = 12.sp)
                SegmentedRow(
                    options = TemperatureUnit.entries.map { it.name to it.label },
                    selected = temperatureUnit.name,
                    onSelect = { name -> settings.setTemperatureUnit(TemperatureUnit.valueOf(name)) },
                )
                Spacer(Modifier.height(10.dp))
                Text("Power", color = Theme.textSecondary, fontSize = 12.sp)
                SegmentedRow(
                    options = PowerUnit.entries.map { it.name to it.label },
                    selected = powerUnit.name,
                    onSelect = { name -> settings.setPowerUnit(PowerUnit.valueOf(name)) },
                )
            }
        }

        item {
            SettingsCard("Charging") {
                Text(
                    "Charge target: $chargeTarget%",
                    color = Theme.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Slider(
                    value = chargeTarget.toFloat(),
                    onValueChange = { settings.setChargeTargetPercent(it.toInt()) },
                    valueRange = 50f..100f,
                    steps = 49,
                )
                Text(
                    "Used by the Charging tab to estimate time to target; the opt-in alert fires once per session.",
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
                Spacer(Modifier.height(10.dp))
                Text("Electricity price per kWh", color = Theme.textSecondary, fontSize = 12.sp)
                // Seeded once from the store: keying this on the flow would re-format the field
                // while the user is still typing.
                var priceText by remember {
                    mutableStateOf(if (tripCostPerKWh > 0) String.format(Locale.US, "%.2f", tripCostPerKWh) else "")
                }
                OutlinedTextField(
                    value = priceText,
                    onValueChange = { text ->
                        priceText = text
                        text.replace(',', '.').toDoubleOrNull()
                            ?.takeIf { it.isFinite() }
                            ?.let { settings.setTripCostPerKWh(it.coerceIn(0.0, 10.0)) }
                    },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "In your local currency. Used for the monthly cost estimate on the Log tab; " +
                        "0 hides it.",
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
            }
        }

        item {
            SettingsCard("Service reminder") {
                val latest by serviceReminder.latest.collectAsStateWithLifecycle()
                val threshold by serviceReminder.thresholdKm.collectAsStateWithLifecycle()
                val miles = distanceUnit == DistanceUnit.MILES
                Text(
                    text = latest?.let { snapshot ->
                        val value = if (miles) snapshot.remainingKm * 0.621371 else snapshot.remainingKm
                        String.format(
                            Locale.US,
                            "Next service in %.0f %s",
                            value,
                            if (miles) "mi" else "km",
                        )
                    } ?: "No service interval reported by this vehicle yet.",
                    color = Theme.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(6.dp))
                Text("Remind me below", color = Theme.textSecondary, fontSize = 12.sp)
                // Thresholds stay stored in kilometers; only the label follows the unit setting.
                SegmentedRow(
                    options = ServiceReminderMonitor.options.map {
                        val label = if (miles) {
                            String.format(Locale.US, "%.0f mi", it * 0.621371)
                        } else {
                            String.format(Locale.US, "%.0f km", it)
                        }
                        it.toInt().toString() to label
                    },
                    selected = threshold.toInt().toString(),
                    onSelect = { value -> serviceReminder.setThresholdKm(value.toDouble()) },
                )
                Text(
                    "One reminder a week at most, and only while vehicle notifications are enabled above.",
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
            }
        }

        item {
            SettingsCard("Alerts") {
                ToggleRow(
                    title = "Vehicle notifications",
                    subtitle = "Charging finished, charge target, fault codes and adapter loss",
                    checked = notificationsEnabled,
                    onCheckedChange = { enabled ->
                        // Permission is requested from this user action, never at launch.
                        if (enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            permissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
                        }
                        settings.setNotificationsEnabled(enabled)
                    },
                )
                Text(
                    "An ongoing notification mirrors charging progress on the lock screen while the car is plugged in.",
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
            }
        }

        item {
            SettingsCard("Backup") {
                CloudBackupCard(store = historyStore)
            }
        }

        item {
            SettingsCard("Android Auto") {
                Text(
                    "Rows shown on the car pane, in order: " +
                        carLayout.tiles.joinToString(", ") { it.title },
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = { showCarLayout = true },
                    colors = ButtonDefaults.buttonColors(containerColor = Theme.subtleFill),
                ) {
                    Text("Edit car layout", color = Theme.textPrimary, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        item {
            SettingsCard("Home screen widget") {
                Text(
                    "State of charge, power and speed on the home screen, refreshed from the live snapshot.",
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
                Spacer(Modifier.height(8.dp))
                val appWidgetManager = remember { AppWidgetManager.getInstance(context) }
                val canPin = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    appWidgetManager.isRequestPinAppWidgetSupported
                Button(
                    onClick = {
                        appWidgetManager.requestPinAppWidget(
                            ComponentName(context, TelemetryWidgetProvider::class.java),
                            null,
                            null,
                        )
                    },
                    enabled = canPin,
                    colors = ButtonDefaults.buttonColors(containerColor = Theme.subtleFill),
                ) {
                    Text("Add widget", color = Theme.textPrimary, fontWeight = FontWeight.SemiBold)
                }
                if (!canPin) {
                    Text(
                        "This launcher does not support pinning. Add the widget from the launcher's widget picker.",
                        color = Theme.textSecondary,
                        fontSize = 10.sp,
                    )
                }
            }
        }

        item {
            SettingsCard("AI log analyzer") {
                AILogAnalysisCard(log = log, vehicleName = manager.vehicleDisplayName)
            }
        }

        item {
            SettingsCard("OBD terminal") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${log.size} recent commands", color = Theme.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                    TextButton(onClick = { showLog = !showLog }) {
                        Text(if (showLog) "Hide" else "Show", color = Theme.electricCyan)
                    }
                    TextButton(onClick = { manager.clearObdLog() }) {
                        Text("Clear", color = Theme.textSecondary)
                    }
                }
                if (showLog) {
                    log.takeLast(25).reversed().forEach { entry ->
                        Column(Modifier.padding(vertical = 4.dp)) {
                            Text(entry.sent, color = Theme.gaugeCyan, fontSize = 11.sp)
                            Text(entry.response.trim(), color = Theme.textSecondary, fontSize = 11.sp)
                        }
                    }
                }
                Text(
                    "Fields every command the active profile decoded, with the response it came " +
                        "from, so a maintainer can review or contribute the decoding.",
                    color = Theme.textSecondary,
                    fontSize = 11.sp,
                )
                val exportScope = rememberCoroutineScope()
                Button(
                    onClick = {
                        val contribution = CommunityContributionBuilder.build(
                            logs = log,
                            profile = manager.selectedProfile,
                            vehicleName = manager.vehicleDisplayName,
                            profileId = profileId.name,
                        )
                        exportScope.launch {
                            ExportShare.share(
                                context = context,
                                fileName = contribution.suggestedFilename,
                                mimeType = ExportShare.jsonMimeType,
                                content = contribution.json(),
                            )
                        }
                    },
                    enabled = log.isNotEmpty(),
                    colors = ButtonDefaults.buttonColors(containerColor = Theme.subtleFill),
                ) {
                    Text(
                        "Export PID contribution",
                        color = Theme.textPrimary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        item {
            SettingsCard("About") {
                Text("VoltLink for Android", color = Theme.textPrimary, fontSize = 14.sp)
                Text(
                    "Native Compose companion to VoltLink iOS. OBD-II / UDS telemetry, diagnostics and demo simulation.",
                    color = Theme.textSecondary,
                    fontSize = 12.sp,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "EQA OBDb signals adapted from OBDb/Mercedes-Benz-EQA (CC BY-SA 4.0); DTC descriptions from Wal33D (MIT).",
                    color = Theme.textSecondary,
                    fontSize = 10.sp,
                )
            }
        }
    }

    if (showCatalog) {
        VehicleCatalogPicker(manager) { showCatalog = false }
    }

    if (showMetricStatus) {
        ProfileMetricStatusSheet(
            profileName = manager.vehicleDisplayName,
            supportedMetrics = manager.selectedProfile.supportedMetrics,
            liveMetrics = liveMetrics,
            isConnected = connectionState.isConnected,
            isDemoMode = isDemoMode,
            isCommunityObdbProfile = profileId == VehicleProfileId.MERCEDES_EQ_A_OBDb,
            onDismiss = { showMetricStatus = false },
        )
    }

    if (showCarLayout) {
        CarTileEditorSheet(
            layout = carLayout,
            supportedMetrics = manager.selectedProfile.supportedMetrics,
            onChange = { settings.setCarTileLayout(it) },
            onDismiss = { showCarLayout = false },
        )
    }
}

@Composable
private fun DeviceRow(device: BleDeviceInfo, onConnect: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Theme.faintFill)
            .clickable(onClick = onConnect)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(device.name, color = Theme.textPrimary, fontSize = 13.sp)
            Text(device.address, color = Theme.textSecondary, fontSize = 11.sp)
        }
        Text("${device.rssi} dBm", color = Theme.textSecondary, fontSize = 11.sp)
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title, color = Theme.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        content()
    }
}

@Composable
private fun ToggleRow(title: String, subtitle: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Theme.textPrimary, fontSize = 14.sp)
            Text(subtitle, color = Theme.textSecondary, fontSize = 11.sp)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun SettingDivider() {
    Spacer(Modifier.height(4.dp))
}

@Composable
private fun SegmentedRow(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        options.forEach { (name, label) ->
            val isSelected = name == selected
            Text(
                text = label,
                color = if (isSelected) Theme.onAccent else Theme.textPrimary,
                fontSize = 13.sp,
                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (isSelected) Theme.electricCyan else Theme.subtleFill)
                    .clickable { onSelect(name) }
                    .padding(vertical = 8.dp, horizontal = 4.dp)
                    .fillMaxWidth(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

private val VehicleProfileId.subtitle: String
    get() = String.format(Locale.US, "%d metrics", makeProfile().supportedMetrics.size)
