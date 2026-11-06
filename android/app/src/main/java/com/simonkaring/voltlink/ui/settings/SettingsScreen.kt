package com.simonkaring.voltlink.ui.settings

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.BuildConfig
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.export.ExportShare
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.vehicles.CommunityContributionBuilder
import com.simonkaring.voltlink.core.vehicles.ServiceReminderMonitor
import com.simonkaring.voltlink.core.vehicles.VehicleProfileId
import com.simonkaring.voltlink.core.widget.TelemetryWidgetProvider
import com.simonkaring.voltlink.data.DistanceUnit
import com.simonkaring.voltlink.data.PowerUnit
import com.simonkaring.voltlink.data.TemperatureUnit
import com.simonkaring.voltlink.services.BleDeviceInfo
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Test tag of the demo-mode switch. Demo mode never starts on its own, so the UI suites have
 * to flip this switch before they can capture simulated telemetry.
 */
const val DEMO_MODE_TOGGLE_TAG = "demoModeToggle"

/** Settings categories. Each one opens a short sub-page instead of extending one long list. */
private enum class SettingsCategory(
    val titleRes: Int,
    val subtitleRes: Int,
) {
    VEHICLE(R.string.settings_category_vehicle, R.string.settings_category_vehicle_subtitle),
    UNITS(R.string.settings_category_units, R.string.settings_category_units_subtitle),
    CHARGING(R.string.settings_category_charging, R.string.settings_category_charging_subtitle),
    ALERTS(R.string.settings_category_alerts, R.string.settings_category_alerts_subtitle),
    INTEGRATIONS(R.string.settings_category_integrations, R.string.settings_category_integrations_subtitle),
    DATA(R.string.settings_category_data, R.string.settings_category_data_subtitle),
    ADVANCED(R.string.settings_category_advanced, R.string.settings_category_advanced_subtitle),
    ABOUT(R.string.settings_category_about, R.string.settings_category_about_subtitle),
}

/** Settings: adapter connection first, then one row per category. */
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
    val chargingStatusEnabled by settings.chargingStatusEnabled.collectAsStateWithLifecycle()
    val alertChargeTarget by settings.alertChargeTargetReached.collectAsStateWithLifecycle()
    val alertChargingFinished by settings.alertChargingFinished.collectAsStateWithLifecycle()
    val alertAdapterDisconnected by settings.alertAdapterDisconnected.collectAsStateWithLifecycle()
    val alertFaultCodes by settings.alertFaultCodes.collectAsStateWithLifecycle()
    val serviceRemindersEnabled by settings.serviceRemindersEnabled.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    // Permission is requested only from a toggle, never at launch.
    val requestNotificationPermission = {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            permissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
        }
    }
    var category by remember { mutableStateOf<SettingsCategory?>(null) }
    var showCatalog by remember { mutableStateOf(false) }
    var showLog by remember { mutableStateOf(false) }
    var showMetricStatus by remember { mutableStateOf(false) }
    var showCarLayout by remember { mutableStateOf(false) }
    val selectedModelName by settings.selectedModelName.collectAsStateWithLifecycle()
    val liveMetrics by manager.liveMetrics.collectAsStateWithLifecycle()
    val carLayout by settings.carTileLayout.collectAsStateWithLifecycle()

    BackHandler(enabled = category != null) { category = null }

    val openCategory = category

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp),
    ) {
        if (openCategory == null) {
            item {
                SettingsCard(stringResource(R.string.settings_connection)) {
                    ToggleRow(
                        title = stringResource(R.string.settings_demo_title),
                        subtitle = stringResource(R.string.settings_demo_subtitle),
                        checked = isDemoMode,
                        onCheckedChange = { manager.setDemoMode(it) },
                        switchModifier = Modifier.testTag(DEMO_MODE_TOGGLE_TAG),
                    )
                    SettingDivider()
                    Text(
                        text = when (val state = connectionState) {
                            is BleConnectionState.Ready -> stringResource(R.string.settings_state_connected, state.deviceName)
                            is BleConnectionState.Connecting ->
                                stringResource(R.string.settings_state_connecting, state.deviceName)
                            is BleConnectionState.Error -> state.message
                            BleConnectionState.Scanning -> stringResource(R.string.settings_state_scanning)
                            BleConnectionState.DemoMode -> stringResource(R.string.settings_state_demo)
                            BleConnectionState.Disconnected -> stringResource(R.string.settings_state_none)
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
                                if (connectionState is BleConnectionState.Scanning) {
                                    stringResource(R.string.settings_scanning)
                                } else {
                                    stringResource(R.string.settings_scan_adapters)
                                },
                                color = Theme.onAccent,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                        TextButton(onClick = { manager.disconnect() }) {
                            Text(stringResource(R.string.settings_disconnect), color = Theme.textSecondary)
                        }
                    }
                    if (devices.isNotEmpty() && !isDemoMode) {
                        Spacer(Modifier.height(4.dp))
                        devices.forEach { device -> DeviceRow(device) { manager.connectToAdapter(device.address) } }
                    }
                }
            }

            SettingsCategory.entries.forEach { entry ->
                item {
                    SettingsCategoryRow(
                        title = stringResource(entry.titleRes),
                        subtitle = stringResource(entry.subtitleRes),
                        onClick = { category = entry },
                    )
                }
            }
        } else {
            item {
                Column(Modifier.fillMaxWidth()) {
                    TextButton(onClick = { category = null }, contentPadding = PaddingValues(0.dp)) {
                        Text(
                            "‹ " + stringResource(R.string.settings_back),
                            color = Theme.electricCyan,
                            fontSize = 13.sp,
                        )
                    }
                    Text(
                        stringResource(openCategory.titleRes),
                        color = Theme.textPrimary,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            when (openCategory) {
                SettingsCategory.VEHICLE -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_vehicle)) {
                            // The whole vehicle line opens the catalog; the explicit button below stays as
                            // the discoverable affordance for the same action.
                            Column(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable { showCatalog = true },
                            ) {
                                Text(
                                    selectedModelName ?: manager.selectedProfile.vehicleName,
                                    color = Theme.textPrimary,
                                    fontSize = 14.sp,
                                )
                                val metricCount = manager.selectedProfile.supportedMetrics.size
                                val metricCountLabel = pluralStringResource(
                                    R.plurals.settings_published_metrics,
                                    metricCount,
                                    metricCount,
                                )
                                Text(
                                    if (selectedModelName != null) {
                                        stringResource(
                                            R.string.settings_profile_metrics,
                                            manager.selectedProfile.vehicleName,
                                            metricCountLabel,
                                        )
                                    } else {
                                        metricCountLabel
                                    },
                                    color = Theme.textSecondary,
                                    fontSize = 12.sp,
                                )
                            }
                            Row {
                                TextButton(
                                    onClick = { showCatalog = true },
                                    contentPadding = PaddingValues(0.dp),
                                ) {
                                    Text(
                                        stringResource(R.string.settings_browse_catalog),
                                        color = Theme.electricCyan,
                                        fontSize = 13.sp,
                                    )
                                }
                                Spacer(Modifier.width(12.dp))
                                TextButton(
                                    onClick = { showMetricStatus = true },
                                    contentPadding = PaddingValues(0.dp),
                                ) {
                                    Text(
                                        stringResource(R.string.settings_metric_status),
                                        color = Theme.electricCyan,
                                        fontSize = 13.sp,
                                    )
                                }
                            }
                        }
                    }

                    item {
                        SettingsCard(stringResource(R.string.settings_service_reminder)) {
                            val latest by serviceReminder.latest.collectAsStateWithLifecycle()
                            val threshold by serviceReminder.thresholdKm.collectAsStateWithLifecycle()
                            val miles = distanceUnit == DistanceUnit.MILES
                            Text(
                                text = latest?.let { snapshot ->
                                    val value = if (miles) snapshot.remainingKm * 0.621371 else snapshot.remainingKm
                                    stringResource(
                                        R.string.settings_next_service,
                                        value,
                                        if (miles) "mi" else "km",
                                    )
                                } ?: stringResource(R.string.settings_no_service_interval),
                                color = Theme.textPrimary,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(stringResource(R.string.settings_remind_below), color = Theme.textSecondary, fontSize = 12.sp)
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
                            Spacer(Modifier.height(10.dp))
                            ToggleRow(
                                title = stringResource(R.string.settings_service_reminder_toggle),
                                subtitle = stringResource(R.string.settings_service_reminder_subtitle),
                                checked = serviceRemindersEnabled,
                                onCheckedChange = { enabled ->
                                    if (enabled) requestNotificationPermission()
                                    settings.setServiceRemindersEnabled(enabled)
                                },
                            )
                            Text(
                                stringResource(R.string.settings_reminder_hint),
                                color = Theme.textSecondary,
                                fontSize = 11.sp,
                            )
                        }
                    }
                }

                SettingsCategory.UNITS -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_units)) {
                            Text(stringResource(R.string.settings_distance_speed), color = Theme.textSecondary, fontSize = 12.sp)
                            SegmentedRow(
                                options = DistanceUnit.entries.map { it.name to it.label },
                                selected = distanceUnit.name,
                                onSelect = { name -> settings.setDistanceUnit(DistanceUnit.valueOf(name)) },
                            )
                            Spacer(Modifier.height(10.dp))
                            Text(stringResource(R.string.settings_temperature), color = Theme.textSecondary, fontSize = 12.sp)
                            SegmentedRow(
                                options = TemperatureUnit.entries.map { it.name to it.label },
                                selected = temperatureUnit.name,
                                onSelect = { name -> settings.setTemperatureUnit(TemperatureUnit.valueOf(name)) },
                            )
                            Spacer(Modifier.height(10.dp))
                            Text(stringResource(R.string.settings_power), color = Theme.textSecondary, fontSize = 12.sp)
                            SegmentedRow(
                                options = PowerUnit.entries.map { it.name to it.label },
                                selected = powerUnit.name,
                                onSelect = { name -> settings.setPowerUnit(PowerUnit.valueOf(name)) },
                            )
                        }
                    }
                }

                SettingsCategory.CHARGING -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_charging)) {
                            Text(
                                stringResource(R.string.settings_charge_target, chargeTarget),
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
                                stringResource(R.string.settings_charge_target_hint),
                                color = Theme.textSecondary,
                                fontSize = 11.sp,
                            )
                            Spacer(Modifier.height(10.dp))
                            Text(stringResource(R.string.settings_price_per_kwh), color = Theme.textSecondary, fontSize = 12.sp)
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
                                stringResource(R.string.settings_price_hint),
                                color = Theme.textSecondary,
                                fontSize = 11.sp,
                            )
                        }
                    }
                }

                SettingsCategory.ALERTS -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_alerts)) {
                            ToggleRow(
                                title = stringResource(R.string.settings_alerts_status_title),
                                subtitle = stringResource(R.string.settings_alerts_status_subtitle),
                                checked = chargingStatusEnabled,
                                onCheckedChange = { enabled ->
                                    if (enabled) requestNotificationPermission()
                                    settings.setChargingStatusEnabled(enabled)
                                },
                            )
                            SettingDivider()
                            ToggleRow(
                                title = stringResource(R.string.settings_alerts_target_title),
                                subtitle = stringResource(R.string.settings_alerts_target_subtitle),
                                checked = alertChargeTarget,
                                onCheckedChange = { enabled ->
                                    if (enabled) requestNotificationPermission()
                                    settings.setAlertChargeTargetReached(enabled)
                                },
                            )
                            SettingDivider()
                            ToggleRow(
                                title = stringResource(R.string.settings_alerts_finished_title),
                                subtitle = stringResource(R.string.settings_alerts_finished_subtitle),
                                checked = alertChargingFinished,
                                onCheckedChange = { enabled ->
                                    if (enabled) requestNotificationPermission()
                                    settings.setAlertChargingFinished(enabled)
                                },
                            )
                            SettingDivider()
                            ToggleRow(
                                title = stringResource(R.string.settings_alerts_adapter_title),
                                subtitle = stringResource(R.string.settings_alerts_adapter_subtitle),
                                checked = alertAdapterDisconnected,
                                onCheckedChange = { enabled ->
                                    if (enabled) requestNotificationPermission()
                                    settings.setAlertAdapterDisconnected(enabled)
                                },
                            )
                            SettingDivider()
                            ToggleRow(
                                title = stringResource(R.string.settings_alerts_faults_title),
                                subtitle = stringResource(R.string.settings_alerts_faults_subtitle),
                                checked = alertFaultCodes,
                                onCheckedChange = { enabled ->
                                    if (enabled) requestNotificationPermission()
                                    settings.setAlertFaultCodes(enabled)
                                },
                            )
                            Text(
                                stringResource(R.string.settings_alerts_hint),
                                color = Theme.textSecondary,
                                fontSize = 11.sp,
                            )
                        }
                    }
                }

                SettingsCategory.INTEGRATIONS -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_android_auto)) {
                            Text(
                                stringResource(R.string.settings_car_rows, carLayout.tiles.joinToString(", ") { it.title }),
                                color = Theme.textSecondary,
                                fontSize = 11.sp,
                            )
                            Spacer(Modifier.height(8.dp))
                            Button(
                                onClick = { showCarLayout = true },
                                colors = ButtonDefaults.buttonColors(containerColor = Theme.subtleFill),
                            ) {
                                Text(
                                    stringResource(R.string.settings_edit_car_layout),
                                    color = Theme.textPrimary,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                    }

                    item {
                        SettingsCard(stringResource(R.string.settings_widget)) {
                            Text(
                                stringResource(R.string.settings_widget_hint),
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
                                Text(
                                    stringResource(R.string.settings_add_widget),
                                    color = Theme.textPrimary,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                            if (!canPin) {
                                Text(
                                    stringResource(R.string.settings_widget_pin_unsupported),
                                    color = Theme.textSecondary,
                                    fontSize = 10.sp,
                                )
                            }
                        }
                    }
                }

                SettingsCategory.DATA -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_backup)) {
                            CloudBackupCard(store = historyStore)
                        }
                    }
                }

                SettingsCategory.ADVANCED -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_obd_terminal)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    stringResource(R.string.settings_recent_commands, log.size),
                                    color = Theme.textSecondary,
                                    fontSize = 12.sp,
                                    modifier = Modifier.weight(1f),
                                )
                                TextButton(onClick = { showLog = !showLog }) {
                                    Text(
                                        if (showLog) stringResource(R.string.action_hide) else stringResource(R.string.action_show),
                                        color = Theme.electricCyan,
                                    )
                                }
                                TextButton(onClick = { manager.clearObdLog() }) {
                                    Text(stringResource(R.string.action_clear), color = Theme.textSecondary)
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
                                stringResource(R.string.settings_obd_contribution_hint),
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
                                    stringResource(R.string.settings_export_contribution),
                                    color = Theme.textPrimary,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                    }
                }

                SettingsCategory.ABOUT -> {
                    item {
                        SettingsCard(stringResource(R.string.settings_about)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Image(
                                    painter = painterResource(R.drawable.ic_brand_mark),
                                    contentDescription = null,
                                    modifier = Modifier.size(52.dp).clip(RoundedCornerShape(12.dp)),
                                )
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(stringResource(R.string.settings_about_app), color = Theme.textPrimary, fontSize = 14.sp)
                                    Text(
                                        stringResource(R.string.settings_about_body),
                                        color = Theme.textSecondary,
                                        fontSize = 12.sp,
                                    )
                                    Text(
                                        stringResource(R.string.settings_about_version, BuildConfig.VERSION_NAME),
                                        color = Theme.textSecondary,
                                        fontSize = 11.sp,
                                    )
                                }
                            }
                            Spacer(Modifier.height(4.dp))
                            Text(
                                stringResource(R.string.settings_about_credits),
                                color = Theme.textSecondary,
                                fontSize = 10.sp,
                            )
                        }
                    }
                }
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
        Text(stringResource(R.string.settings_device_rssi, device.rssi), color = Theme.textSecondary, fontSize = 11.sp)
    }
}

@Composable
private fun SettingsCategoryRow(title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = Theme.textSecondary, fontSize = 11.sp)
        }
        Text("›", color = Theme.textSecondary, fontSize = 22.sp)
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
private fun ToggleRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    switchModifier: Modifier = Modifier,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Theme.textPrimary, fontSize = 14.sp)
            Text(subtitle, color = Theme.textSecondary, fontSize = 11.sp)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange, modifier = switchModifier)
    }
}

@Composable
private fun SettingDivider() {
    Spacer(Modifier.height(4.dp))
}

@Composable
internal fun SegmentedRow(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
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
