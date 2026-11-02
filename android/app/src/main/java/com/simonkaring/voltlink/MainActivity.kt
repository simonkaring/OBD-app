package com.simonkaring.voltlink

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.core.shortcuts.AppCommand
import com.simonkaring.voltlink.core.shortcuts.AppShortcuts
import com.simonkaring.voltlink.services.DtcScannerService
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.dashboard.DashboardScreen
import com.simonkaring.voltlink.ui.dashboard.DemoControlsSheet
import com.simonkaring.voltlink.ui.dashboard.HudScreen
import com.simonkaring.voltlink.ui.diagnostics.DiagnosticsScreen
import com.simonkaring.voltlink.ui.settings.SettingsScreen
import com.simonkaring.voltlink.ui.theme.Theme
import com.simonkaring.voltlink.ui.theme.VoltLinkTheme

class MainActivity : ComponentActivity() {
    /** Shortcut/assistant action waiting for the composition to start handling it. */
    private var pendingCommand by mutableStateOf<AppCommand?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingCommand = commandFor(intent)
        val app = application as VoltLinkApplication
        setContent {
            VoltLinkTheme {
                VoltLinkRoot(
                    vehicleData = app.vehicleData,
                    scanner = app.dtcScanner,
                    tripTracker = app.tripTracker,
                    chargingTracker = app.chargingTracker,
                    historyStore = app.historyStore,
                    serviceReminder = app.serviceReminder,
                    command = pendingCommand,
                    onCommandHandled = { pendingCommand = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingCommand = commandFor(intent)
    }

    private fun commandFor(intent: Intent?): AppCommand? = when (intent?.action) {
        AppShortcuts.ACTION_TOGGLE_TRIP -> AppCommand.TOGGLE_TRIP
        AppShortcuts.ACTION_SCAN_DTCS -> AppCommand.SCAN_DTCS
        AppShortcuts.ACTION_OPEN_CHARGING -> AppCommand.OPEN_CHARGING
        else -> null
    }
}

private enum class Tab(val label: String, val icon: ImageVector) {
    TELEMETRY("Telemetry", Icons.Filled.Insights),
    LOG("Log", Icons.Filled.Route),
    CHARGING("Charging", Icons.Filled.Bolt),
    DIAGNOSTICS("Diagnostics", Icons.Filled.Build),
    SETTINGS("Settings", Icons.Filled.Settings),
}

@Composable
private fun VoltLinkRoot(
    vehicleData: VehicleDataManager,
    scanner: DtcScannerService,
    tripTracker: com.simonkaring.voltlink.services.TripTracker,
    chargingTracker: com.simonkaring.voltlink.services.ChargingTracker,
    historyStore: com.simonkaring.voltlink.data.HistoryStore,
    serviceReminder: com.simonkaring.voltlink.core.vehicles.ServiceReminderMonitor,
    command: AppCommand?,
    onCommandHandled: () -> Unit,
) {
    var tab by remember { mutableStateOf(Tab.TELEMETRY) }
    var showDemoSheet by remember { mutableStateOf(false) }
    var showHud by remember { mutableStateOf(false) }
    val settings = vehicleData.settings
    val distance by settings.distanceUnit.collectAsStateWithLifecycle()
    val temperature by settings.temperatureUnit.collectAsStateWithLifecycle()
    val power by settings.powerUnit.collectAsStateWithLifecycle()
    val units = UnitPrefs(distance, temperature, power)

    BluetoothPermissionGate()

    // Launcher shortcuts and assistant intents arrive as commands, never as deep links.
    LaunchedEffect(command) {
        when (command) {
            null -> Unit
            AppCommand.TOGGLE_TRIP -> {
                if (tripTracker.state.value.isRecording) {
                    tripTracker.stop(vehicleData.telemetry.value.stateOfChargePct)
                } else {
                    tripTracker.start(
                        vehicleData.telemetry.value.stateOfChargePct,
                        vehicleData.vehicleDisplayName,
                    )
                }
                tab = Tab.LOG
                onCommandHandled()
            }
            AppCommand.SCAN_DTCS -> {
                tab = Tab.DIAGNOSTICS
                scanner.scan()
                onCommandHandled()
            }
            AppCommand.OPEN_CHARGING -> {
                tab = Tab.CHARGING
                onCommandHandled()
            }
        }
    }

    if (showHud) {
        HudScreen(manager = vehicleData, units = units) { showHud = false }
        return
    }

    Scaffold(
        containerColor = Theme.backgroundDark,
        bottomBar = {
            NavigationBar(containerColor = Theme.cardBackground) {
                Tab.entries.forEach { entry ->
                    NavigationBarItem(
                        selected = tab == entry,
                        onClick = { tab = entry },
                        icon = { Icon(entry.icon, contentDescription = entry.label) },
                        label = { Text(entry.label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Theme.onAccent,
                            selectedTextColor = Theme.electricCyan,
                            indicatorColor = Theme.electricCyan,
                            unselectedIconColor = Theme.textSecondary,
                            unselectedTextColor = Theme.textSecondary,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                Tab.TELEMETRY -> DashboardScreen(
                    manager = vehicleData,
                    units = units,
                    onOpenDemoControls = { showDemoSheet = true },
                    onOpenHud = { showHud = true },
                )
                Tab.LOG -> com.simonkaring.voltlink.ui.trips.TripsScreen(
                    manager = vehicleData,
                    tracker = tripTracker,
                    units = units,
                )
                Tab.CHARGING -> com.simonkaring.voltlink.ui.charging.ChargingScreen(
                    manager = vehicleData,
                    tracker = chargingTracker,
                    store = historyStore,
                    units = units,
                )
                Tab.DIAGNOSTICS -> DiagnosticsScreen(manager = vehicleData, scanner = scanner)
                Tab.SETTINGS -> SettingsScreen(
                    manager = vehicleData,
                    serviceReminder = serviceReminder,
                    historyStore = historyStore,
                )
            }
        }
    }

    if (showDemoSheet) {
        DemoControlsSheet(manager = vehicleData) { showDemoSheet = false }
    }
}

/** Requests the BLE permissions needed to scan for an adapter on first launch. */
@Composable
private fun BluetoothPermissionGate() {
    val context = LocalContext.current
    val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    LaunchedEffect(Unit) {
        val missing = permissions.filter {
            context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) launcher.launch(missing.toTypedArray())
    }
}
