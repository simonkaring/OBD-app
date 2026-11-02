package com.simonkaring.voltlink.services

import android.content.Context
import com.simonkaring.voltlink.core.demo.MockDrivingSimulation
import com.simonkaring.voltlink.core.demo.MockObdAdapter
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.obd.ObdConnection
import com.simonkaring.voltlink.core.obd.ObdLogEntry
import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.core.vehicles.VehicleModelEntry
import com.simonkaring.voltlink.core.vehicles.VehicleProfile
import com.simonkaring.voltlink.core.vehicles.VehicleProfileId
import com.simonkaring.voltlink.data.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Main-actor telemetry facade: owns the active connection (real BLE or demo), initialises the
 * selected profile, drives [TelemetryPollingLoop], and publishes the decoded snapshot plus the
 * set of live metrics. Android counterpart of the iOS `VehicleDataManager`.
 */
class VehicleDataManager(
    private val context: Context,
    private val scope: CoroutineScope,
) {
    val settings = SettingsStore(context)

    private val _selectedProfileId = MutableStateFlow(settings.selectedProfile.value)
    val selectedProfileId: StateFlow<VehicleProfileId> = _selectedProfileId.asStateFlow()

    var selectedProfile: VehicleProfile = _selectedProfileId.value.makeProfile()
        private set

    val reducer = TelemetryReducer(selectedProfile.batteryUsableCapacityKWh)

    private val _telemetry = MutableStateFlow(TelemetrySnapshot())
    val telemetry: StateFlow<TelemetrySnapshot> = _telemetry.asStateFlow()

    private val _liveMetrics = MutableStateFlow<Set<TelemetryMetric>>(emptySet())
    val liveMetrics: StateFlow<Set<TelemetryMetric>> = _liveMetrics.asStateFlow()

    private val _connectionState = MutableStateFlow<BleConnectionState>(BleConnectionState.Disconnected)
    val connectionState: StateFlow<BleConnectionState> = _connectionState.asStateFlow()

    // Demo mode is never persisted: every launch starts disconnected and the simulation only
    // runs while the user has it switched on.
    private val _isDemoMode = MutableStateFlow(false)
    val isDemoMode: StateFlow<Boolean> = _isDemoMode.asStateFlow()

    private val bleConnection = BleObdConnection(context, scope)
    private val mockAdapter = MockObdAdapter(scope)
    private val demoProfile = com.simonkaring.voltlink.core.demo.DemoProfile()
    private var connection: ObdConnection = bleConnection

    val discoveredDevices get() = bleConnection.discoveredDevices
    val obdLog: StateFlow<List<ObdLogEntry>> get() = connection.log
    val discoveredAdapterName: String? get() = (connectionState.value as? BleConnectionState.Ready)?.deviceName

    private val pollingLoop = TelemetryPollingLoop(scope)
    private var stateJob: Job? = null
    private var initializeJob: Job? = null
    private var isCommandSessionActive = false
    private var isInitializing = false

    private val commandMetrics = mutableMapOf<String, MutableSet<TelemetryMetric>>()
    private val commandMisses = mutableMapOf<String, Int>()

    init {
        configurePollingLoop()
        observeConnectionState()
    }

    private fun observeConnectionState() {
        stateJob?.cancel()
        val active = connection
        _connectionState.value = active.state.value
        stateJob = scope.launch {
            active.state.collect { state ->
                if (connection === active) _connectionState.value = state
            }
        }
    }

    // ---------------------------------------------------------------- connection lifecycle

    /**
     * Switches the telemetry source. Turning demo on starts the simulation and the poll loop;
     * turning it off stops both and returns to the (disconnected) BLE adapter.
     */
    fun setDemoMode(enabled: Boolean) {
        if (_isDemoMode.value == enabled) return
        stopPolling()
        connection.disconnect()
        _isDemoMode.value = enabled
        connection = if (enabled) mockAdapter else bleConnection
        if (enabled) mockAdapter.startSimulation()
        observeConnectionState()
        // The previous source's readings are gone; start from an empty snapshot so no stale
        // demo number survives the switch.
        reducer.reset()
        publish()
        if (enabled) startPolling()
    }

    fun startScan() {
        if (_isDemoMode.value) setDemoMode(false)
        bleConnection.startScan()
    }

    fun stopScan() = bleConnection.stopScan()

    fun connectToAdapter(address: String? = null) {
        if (_isDemoMode.value) setDemoMode(false)
        scope.launch {
            connection.connect(address ?: settings.lastAdapterAddress)
            if (connection.state.value.isConnected) {
                address?.let { settings.lastAdapterAddress = it }
                initializeProfile()
            }
        }
    }

    fun disconnect() {
        stopPolling()
        connection.disconnect()
        reducer.resetValidity()
        publish()
    }

    /** Name shown for the current vehicle: the catalog row when one was picked, else the profile. */
    val vehicleDisplayName: String
        get() = settings.selectedModelName.value ?: selectedProfile.vehicleName

    /** Applies a catalog row: it selects the profile the row maps to and remembers its name. */
    fun selectVehicle(model: VehicleModelEntry) {
        settings.setSelectedModel(model.id, model.fullName)
        selectProfile(model.profileId, keepVehicle = true)
    }

    /** Picking a profile directly drops the catalog row so the two never disagree. */
    fun selectProfile(id: VehicleProfileId, keepVehicle: Boolean = false) {
        if (!keepVehicle) settings.setSelectedModel(null, null)
        if (id == _selectedProfileId.value) return
        _selectedProfileId.value = id
        settings.setProfile(id)
        selectedProfile = id.makeProfile()
        reducer.updateCapacity(selectedProfile.batteryUsableCapacityKWh)
        reducer.resetValidity()
        publish()
        if (!_isDemoMode.value && connection.state.value.isConnected) {
            scope.launch { initializeProfile() }
        }
    }

    /** Sends the profile's initialisation commands, verifying each acknowledgement. */
    suspend fun initializeProfile() {
        if (isInitializing) return
        isInitializing = true
        stopPolling()
        reducer.resetValidity()
        publish()
        var ready = true
        for (command in selectedProfile.initializationCommands) {
            if (!connection.state.value.isConnected) {
                ready = false
                break
            }
            val result = connection.sendCommand(command)
            val raw = result.getOrNull() ?: ""
            if (!isSupportedResponse(command, raw)) {
                ready = false
                break
            }
        }
        isInitializing = false
        if (ready) startPolling() else handleRoutingFailure("profile initialisation")
    }

    private fun handleRoutingFailure(stage: String) {
        stopPolling()
        reducer.resetValidity()
        publish()
        connection.disconnect()
        _connectionState.value = BleConnectionState.Error("Adapter routing failed at $stage. Reconnect the scanner.")
    }

    fun startPolling() {
        pollingLoop.commands = {
            // Demo mode polls the simulated adapter's own set so the dashboard shows power,
            // SoC and generic metrics even when the selected profile (e.g. EQA 250) only
            // publishes pack voltage.
            if (_isDemoMode.value) demoProfile.pollingCommands else selectedProfile.pollingCommands
        }
        pollingLoop.start()
    }

    private fun activeProfile(): VehicleProfile = if (_isDemoMode.value) demoProfile else selectedProfile

    fun stopPolling() = pollingLoop.stop()

    // ---------------------------------------------------------------- command sessions

    /** Takes the adapter away from polling for a diagnostic scan or terminal command. */
    fun beginCommandSession(): Boolean {
        if (isCommandSessionActive || isInitializing) return false
        if (!connection.state.value.isConnected) return false
        stopPolling()
        pollingLoop.resetIndex()
        isCommandSessionActive = true
        return true
    }

    fun endCommandSession(restoreProfile: Boolean = true) {
        isCommandSessionActive = false
        if (_isDemoMode.value || !connection.state.value.isConnected) return
        if (restoreProfile) {
            scope.launch { initializeProfile() }
        } else {
            startPolling()
        }
    }

    suspend fun sendCommandResult(command: String): Result<String> = connection.sendCommand(command)

    /** Runs an AT command sequence and reports whether every command was acknowledged. */
    suspend fun sendSetupCommands(commands: List<String>): Boolean {
        for (command in commands) {
            val raw = connection.sendCommand(command).getOrNull() ?: return false
            if (!isSupportedResponse(command, raw)) return false
        }
        return true
    }

    // ---------------------------------------------------------------- polling internals

    private fun configurePollingLoop() {
        pollingLoop.isConnected = { connection.state.value.isConnected }
        pollingLoop.send = { command -> connection.sendCommand(command) }
        pollingLoop.handleRead = { command, raw ->
            val updates = activeProfile().parseResponses(command, raw)
            val applied = if (updates.isEmpty()) false else applyUpdates(updates, command)
            if (!applied) recordMiss(command)
            applied
        }
        pollingLoop.handleReadFailure = { command -> recordMiss(command) }
        pollingLoop.handleControl = { command, result ->
            val raw = result.getOrNull()
            raw != null && isSupportedResponse(command, raw)
        }
        pollingLoop.handleControlFailure = { command -> handleRoutingFailure(command) }
    }

    private fun applyUpdates(updates: List<TelemetryUpdate>, sourceCommand: String?): Boolean {
        val applied = reducer.applyAll(updates, sourceCommand = sourceCommand)
        if (!applied) return false
        if (sourceCommand != null) {
            val metrics = commandMetrics.getOrPut(sourceCommand) { mutableSetOf() }
            updates.forEach { metrics += reducer.metricsFor(it) }
            commandMisses[sourceCommand] = 0
        }
        publish()
        return true
    }

    fun applyUpdate(update: TelemetryUpdate) {
        if (reducer.apply(update)) publish()
    }

    private fun publish() {
        _telemetry.value = reducer.snapshot
        _liveMetrics.value = reducer.liveMetrics
    }

    private fun recordMiss(command: String) {
        val metrics = commandMetrics[command] ?: return
        val misses = (commandMisses[command] ?: 0) + 1
        commandMisses[command] = misses
        if (misses < 3) return
        // Three consecutive misses means the PID is unsupported or the module stopped
        // answering: drop its metrics so stale numbers disappear from the dashboard.
        val removed = metrics.toSet()
        reducer.resetValidity()
        _liveMetrics.value = reducer.liveMetrics - removed
        _telemetry.value = reducer.snapshot
    }

    fun isSupportedResponse(command: String, rawResponse: String): Boolean {
        val request = command.replace(" ", "").uppercase()
        val lines = com.simonkaring.voltlink.core.obd.IsoTp.cleanElmResponse(rawResponse)
            .uppercase()
            .split("\n")
            .map { it.trim() }
        return when {
            request == "ATZ" -> lines.any { it.contains("ELM") || it.contains("OBD") || it.contains("STN") }
            request.startsWith("AT") -> lines.contains("OK")
            request.startsWith("10") -> {
                val expected = "50" + request.takeLast(2)
                com.simonkaring.voltlink.core.obd.IsoTp.assemblePayloads(rawResponse)
                    .any { it.payload.startsWith(expected, ignoreCase = true) }
            }
            else -> true
        }
    }

    /** GPS-derived speed for vehicles whose profile cannot report it. */
    fun applyExternalSpeed(speedKmH: Double, timestamp: java.time.Instant = java.time.Instant.now()) {
        if (_isDemoMode.value) return
        reducer.applyExternalSpeed(speedKmH, timestamp)
        publish()
    }

    fun needsExternalSpeed(at: java.time.Instant = java.time.Instant.now()): Boolean = reducer.needsExternalSpeed(at)

    fun clearExternalSpeed() {
        reducer.clearExternalSpeed()
        publish()
    }

    fun clearObdLog() = connection.clearLog()

    /** Waits briefly for a single command, used by the terminal's "send" button. */
    suspend fun sendTerminalCommand(command: String): String {
        val result = withTimeoutOrNull(6_000) { connection.sendCommand(command) }
        return result?.getOrNull() ?: "ERROR: Command Timeout"
    }

    val simulation: MockDrivingSimulation get() = mockAdapter.simulation
}
