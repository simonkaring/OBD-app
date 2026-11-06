import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#endif

public struct SettingsView: View {
    public var vehicleData: VehicleDataManager
    @Bindable public var tripTracker: TripTrackingManager

    @AppStorage("developerModeEnabled") private var developerModeEnabled: Bool = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    public init(vehicleData: VehicleDataManager, tripTracker: TripTrackingManager? = nil) {
        self.vehicleData = vehicleData
        self.tripTracker = tripTracker ?? AppEnvironment.shared.tripTracker
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Demo / Simulation Mode",
                        isOn: Binding(
                            get: { vehicleData.isDemoMode },
                            set: { vehicleData.toggleDemoMode($0) }
                        )
                    )
                    .disabled(vehicleData.isCommandSessionActive)

                    if vehicleData.isDemoMode {
                        NavigationLink("Demo Simulation Controls") {
                            DemoSimulationSettingsView(vehicleData: vehicleData)
                        }
                    }

                    NavigationLink("Bluetooth Adapter") {
                        BluetoothSettingsView(vehicleData: vehicleData)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text(
                        "Demo mode streams simulated telemetry without an adapter. VoltLink reconnects to the last adapter when Bluetooth becomes available."
                    )
                }

                Section {
                    NavigationLink("Vehicle Profile") {
                        VehicleSettingsView(vehicleData: vehicleData)
                    }

                    NavigationLink("Maintenance") {
                        MaintenanceSettingsView(vehicleData: vehicleData)
                    }

                    NavigationLink("SOC Reference") {
                        SOCReferenceSettingsView(vehicleData: vehicleData)
                            .id(
                                "\(vehicleData.selectedVehicle.id).\(vehicleData.selectedModelYear ?? 0).\(vehicleData.selectedProfileID.rawValue).\(vehicleData.isDemoMode)"
                            )
                    }
                } header: {
                    Text("Vehicle")
                }

                Section {
                    NavigationLink("Display & Units") {
                        DisplayUnitsSettingsView()
                    }

                    NavigationLink("Charging & Trips") {
                        ChargingTripSettingsView(tripTracker: tripTracker)
                    }

                    NavigationLink("Notifications") {
                        NotificationSettingsView()
                    }
                } header: {
                    Text("Preferences")
                }

                Section {
                    NavigationLink("Routes & iCloud") {
                        PrivacySettingsView(tripTracker: tripTracker)
                    }
                } header: {
                    Text("Data & Privacy")
                }

                Section {
                    NavigationLink("CarPlay Tiles") {
                        CarPlayTileEditorView(vehicleData: vehicleData)
                    }
                } header: {
                    Text("CarPlay")
                }

                Section {
                    Toggle("Developer Mode", isOn: $developerModeEnabled)

                    if developerModeEnabled {
                        NavigationLink("Profile Metric Status") {
                            ProfileMetricStatusView(vehicleData: vehicleData)
                        }

                        NavigationLink("Calibration") {
                            CalibrationSettingsView(vehicleData: vehicleData)
                        }

                        NavigationLink("OBD Terminal") {
                            OBDTerminalView(vehicleData: vehicleData)
                        }
                    }
                } header: {
                    Text("Developer")
                }

                Section {
                    HStack(spacing: 12) {
                        Image("BrandMark")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VoltLink")
                                .font(.headline)
                            Text("Live EV telemetry & diagnostics")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("App Information")
                }
            }
            .navigationTitle("Settings")
            .inlineTitleDisplayMode()
        }
    }
}

private struct DemoSimulationSettingsView: View {
    var vehicleData: VehicleDataManager

    @State private var targetSpeed: Double = 50.0
    @State private var regenLevel: Double = 0.5

    private var units: UnitPreferences { .shared }

    private var mockEngine: MockDrivingSimulation? {
        (vehicleData.obdConnection as? MockOBDAdapter)?.simulationEngine
    }

    var body: some View {
        Form {
            if let engine = mockEngine {
                Section {
                    Picker(
                        "Preset Scenario",
                        selection: Binding(
                            get: { engine.scenario },
                            set: { engine.scenario = $0 }
                        )
                    ) {
                        ForEach(DemoScenario.allCases) { scenario in
                            Text(scenario.rawValue).tag(scenario)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Simulated Speed: \(units.speed(kilometersPerHour: targetSpeed, decimals: 0))")
                            .font(.subheadline)
                        Slider(value: $targetSpeed, in: 0...160, step: 5) { _ in
                            engine.userSpeedOverride = targetSpeed
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Regen Braking Force: \(Int(regenLevel * 100))%")
                            .font(.subheadline)
                        Slider(value: $regenLevel, in: 0...1.0) { _ in
                            engine.userRegenOverride = regenLevel
                        }
                    }

                    Button("Reset Manual Overrides") {
                        engine.userSpeedOverride = nil
                        engine.userThrottleOverride = nil
                        engine.userRegenOverride = nil
                        targetSpeed = 50.0
                        regenLevel = 0.5
                    }
                    .foregroundStyle(Theme.electricCyan)
                } header: {
                    Text("Simulation")
                }

                Section {
                    HStack {
                        Button("Inject DTC Fault (P0A80)") {
                            engine.scenario = .faultInjection
                            engine.injectedFaultCode = "P0A80"
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.highPowerAmber)

                        Spacer()

                        Button("Clear Fault Codes") {
                            engine.injectedFaultCode = nil
                            engine.scenario = .cityDriving
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.regenGreen)
                    }
                } header: {
                    Text("Fault Injection")
                }
            } else {
                Text("Enable Demo / Simulation Mode to use these controls.")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle("Demo Simulation")
        .inlineTitleDisplayMode()
    }
}

private struct VehicleSettingsView: View {
    var vehicleData: VehicleDataManager
    @State private var showVehiclePicker = false

    var body: some View {
        Form {
            Section {
                Button {
                    showVehiclePicker = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Vehicle")
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                            Text(vehicleData.vehicleName)
                                .font(.caption)
                                .foregroundStyle(Theme.electricCyan)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Profile")
            }

        }
        .navigationTitle("Vehicle")
        .inlineTitleDisplayMode()
        .sheet(isPresented: $showVehiclePicker) {
            VehicleProfilePickerSheet(vehicleData: vehicleData)
        }
    }
}

private struct CalibrationSettingsView: View {
    var vehicleData: VehicleDataManager

    var body: some View {
        Form {
            Section {
                if vehicleData.isCalibrating {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Calibrating profile metrics...")
                                .font(.subheadline)
                                .foregroundStyle(Theme.electricCyan)
                            Spacer()
                            Text("\(Int(vehicleData.calibrationProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        ProgressView(value: vehicleData.calibrationProgress, total: 1.0)
                            .tint(Theme.electricCyan)
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack {
                        Button {
                            vehicleData.startCalibration()
                        } label: {
                            Label(
                                vehicleData.calibratedCommands == nil ? "Calibrate Live Metrics" : "Re-calibrate Metrics",
                                systemImage: "slider.horizontal.3"
                            )
                            .foregroundStyle(vehicleData.connectionState.isConnected ? Theme.electricCyan : .secondary)
                        }
                        .disabled(!vehicleData.connectionState.isConnected)

                        Spacer()

                        if let summary = vehicleData.calibrationSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(Theme.regenGreen)

                            Button {
                                vehicleData.resetCalibration()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reset calibration")
                        }
                    }
                    if !vehicleData.connectionState.isConnected {
                        Text("Connect to your OBD adapter or enable Demo Mode to run metric calibration.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                Text("Calibration")
            }
        }
        .navigationTitle("Calibration")
        .inlineTitleDisplayMode()
    }
}

private struct DisplayUnitsSettingsView: View {
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false

    private var units: UnitPreferences { .shared }

    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
            } header: {
                Text("Display")
            } footer: {
                Text("Prevents the screen from dimming and locking while VoltLink is open. This may increase battery use.")
            }

            Section {
                Picker(
                    "Distance & Speed",
                    selection: Binding(
                        get: { units.distanceUnit },
                        set: { units.distanceUnit = $0 })
                ) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text("\(unit.displayName) (\(unit.symbol))").tag(unit)
                    }
                }

                Picker(
                    "Temperature",
                    selection: Binding(
                        get: { units.temperatureUnit },
                        set: { units.temperatureUnit = $0 })
                ) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text("\(unit.displayName) (\(unit.symbol))").tag(unit)
                    }
                }

                Picker(
                    "Power",
                    selection: Binding(
                        get: { units.powerUnit },
                        set: { units.powerUnit = $0 })
                ) {
                    ForEach(PowerUnit.allCases) { unit in
                        Text("\(unit.displayName) (\(unit.symbol))").tag(unit)
                    }
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Telemetry is recorded in metric units; only the display changes. Exports always keep metric values for interoperability.")
            }
        }
        .navigationTitle("Display & Units")
        .inlineTitleDisplayMode()
    }
}

private struct ChargingTripSettingsView: View {
    @Bindable var tripTracker: TripTrackingManager

    @AppStorage("electricityPricePerKWh") private var electricityPricePerKWh: Double = 0
    @AppStorage(ChargingTarget.socKey) private var chargeTargetSOC = ChargingTarget.defaultSOC

    var body: some View {
        Form {
            Section {
                Picker("Charge Target", selection: $chargeTargetSOC) {
                    ForEach(ChargingTarget.options, id: \.self) { option in
                        Text("\(Int(option))%").tag(option)
                    }
                }
            } header: {
                Text("Charging")
            } footer: {
                Text(
                    "The Charging tab estimates the remaining time to this target and to 100% from the session's charging curve, including the taper above 80%."
                )
            }

            Section {
                HStack {
                    Text("Electricity Price")
                    Spacer()
                    TextField("0.00", value: $electricityPricePerKWh, format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                    Text("per kWh")
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Trip Cost Estimate")
            } footer: {
                Text("Used for the cost summary on the Log tab. Set it to 0 to hide the estimate.")
            }

            Section {
                Toggle("Automatic Trip Recording", isOn: $tripTracker.isAutoTripEnabled)

                if tripTracker.isAutoTripEnabled {
                    Picker("Auto-Stop Delay (Stationary)", selection: $tripTracker.autoStopDelaySeconds) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Trips")
            }
        }
        .navigationTitle("Charging & Trips")
        .inlineTitleDisplayMode()
    }
}

private struct NotificationSettingsView: View {
    @AppStorage(NotificationService.PreferenceKey.chargeTargetReached) private var notifyChargeTarget = false
    @AppStorage(NotificationService.PreferenceKey.chargingFinished) private var notifyChargingFinished = false
    @AppStorage(NotificationService.PreferenceKey.adapterDisconnected) private var notifyAdapterDisconnected = false
    @AppStorage(NotificationService.PreferenceKey.faultCodes) private var notifyFaultCodes = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Charge Target Reached",
                    isOn: Binding(
                        get: { notifyChargeTarget },
                        set: { enabled in
                            notifyChargeTarget = enabled
                            if enabled { Task { await NotificationService.shared.requestAuthorizationIfNeeded() } }
                        }))
                Toggle(
                    "Charging Finished",
                    isOn: Binding(
                        get: { notifyChargingFinished },
                        set: { enabled in
                            notifyChargingFinished = enabled
                            if enabled { Task { await NotificationService.shared.requestAuthorizationIfNeeded() } }
                        }))
                Toggle(
                    "Adapter Disconnected During a Trip",
                    isOn: Binding(
                        get: { notifyAdapterDisconnected },
                        set: { enabled in
                            notifyAdapterDisconnected = enabled
                            if enabled { Task { await NotificationService.shared.requestAuthorizationIfNeeded() } }
                        }))
                Toggle(
                    "Fault Codes Found",
                    isOn: Binding(
                        get: { notifyFaultCodes },
                        set: { enabled in
                            notifyFaultCodes = enabled
                            if enabled { Task { await NotificationService.shared.requestAuthorizationIfNeeded() } }
                        }))
            } header: {
                Text("Notifications")
            } footer: {
                Text("VoltLink asks for permission the first time one of these is enabled. Notifications never include raw vehicle data.")
            }
        }
        .navigationTitle("Notifications")
        .inlineTitleDisplayMode()
    }
}

private struct PrivacySettingsView: View {
    var tripTracker: TripTrackingManager

    @AppStorage(CloudSyncPreference.enabledKey) private var iCloudSyncEnabled = false

    var body: some View {
        Form {
            Section("GPS Route Recording") {
                switch tripTracker.locationAuthorizationStatus {
                case .notDetermined:
                    Button("Enable GPS Route Recording", systemImage: "location") {
                        tripTracker.requestLocationAuthorization()
                    }
                    Text("Allow location while using VoltLink to save routes and provide GPS speed for your vehicle.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                #if os(iOS)
                case .authorizedWhenInUse:
                    Label("GPS recording enabled while using VoltLink", systemImage: "location.fill")
                        .foregroundStyle(Theme.regenGreen)
                    Button("Allow Background Route Recording", systemImage: "location.circle") {
                        tripTracker.requestBackgroundLocationAuthorization()
                    }
                    Text("Background access keeps an active route recording while the app is minimized or your phone is locked.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                #endif

                case .authorizedAlways:
                    Label("GPS route recording enabled in the background", systemImage: "location.fill")
                        .foregroundStyle(Theme.regenGreen)

                case .denied:
                    Text("GPS route recording is disabled.")
                        .foregroundStyle(Theme.textSecondary)
                    #if os(iOS)
                    Link("Open VoltLink Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    #endif

                case .restricted:
                    Text("GPS route recording is restricted on this device.")
                        .foregroundStyle(Theme.textSecondary)

                @unknown default:
                    EmptyView()
                }
            }

            Section {
                Toggle("Sync History with iCloud", isOn: $iCloudSyncEnabled)
                if let syncWarning = AppEnvironment.shared.syncWarning {
                    Text(syncWarning)
                        .font(.caption)
                        .foregroundStyle(Theme.highPowerAmber)
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text(
                    "Trips, charging sessions, and battery health are mirrored to your private iCloud database so they survive a device change. Off by default. Takes effect the next time VoltLink starts, and needs a build signed with the iCloud capability."
                )
            }
        }
        .navigationTitle("Routes & iCloud")
        .inlineTitleDisplayMode()
    }
}

private struct BluetoothSettingsView: View {
    var vehicleData: VehicleDataManager
    @AppStorage(BluetoothManager.autoReconnectKey) private var autoReconnectToAdapter = true

    var body: some View {
        Form {
            Section {
                NavigationLink("Scan Nearby BLE Devices") {
                    AdapterScanView(vehicleData: vehicleData)
                }
                Toggle("Reconnect to Last Adapter", isOn: $autoReconnectToAdapter)
            } header: {
                Text("Bluetooth Adapter")
            } footer: {
                Text("VoltLink reconnects to the adapter used last when Bluetooth becomes available, without scanning again.")
            }
        }
        .navigationTitle("Bluetooth")
        .inlineTitleDisplayMode()
    }
}

private struct MaintenanceSettingsView: View {
    var vehicleData: VehicleDataManager
    @AppStorage(ServiceReminderMonitor.Key.thresholdKm) private var thresholdKm = ServiceReminderMonitor.defaultThresholdKm
    @AppStorage(NotificationService.PreferenceKey.serviceDue) private var notifyServiceDue = false

    private var stored: ServiceIntervalSnapshot? {
        ServiceReminderMonitor().snapshot(for: vehicleData.vehicleName)
    }

    /// Prefers the live reading so the section updates while connected, and falls back to the
    /// last value the monitor stored.
    private var displayedKm: Double? {
        if let live = vehicleData.latestTelemetry.communityValues?[.serviceDistance], live.isFinite {
            return live
        }
        return stored?.remainingKm
    }

    var body: some View {
        Form {
            Section {
                if let km = displayedKm {
                    LabeledContent("Service due in") {
                        Text(km <= 0 ? "Overdue" : UnitPreferences.shared.distance(kilometers: km, decimals: 0))
                            .foregroundStyle(km <= thresholdKm ? Theme.highPowerAmber : Theme.textPrimary)
                    }

                    if let stored {
                        Text("Last reported \(stored.observedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("This vehicle profile does not report a service interval. The Mercedes-Benz EQA 250 (OBDb) profile provides one.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Picker("Remind at", selection: $thresholdKm) {
                    ForEach(ServiceReminderMonitor.options, id: \.self) { option in
                        Text(UnitPreferences.shared.distance(kilometers: option, decimals: 0)).tag(option)
                    }
                }

                Toggle(
                    "Service Due Reminder",
                    isOn: Binding(
                        get: { notifyServiceDue },
                        set: { enabled in
                            notifyServiceDue = enabled
                            if enabled { Task { await NotificationService.shared.requestAuthorizationIfNeeded() } }
                        }))
            } header: {
                Text("Maintenance")
            } footer: {
                Text(
                    "Distance to the next service is read from the vehicle while connected. The reminder fires at most once a week, per vehicle, when the reported distance drops below the threshold."
                )
            }
        }
        .navigationTitle("Maintenance")
        .inlineTitleDisplayMode()
    }
}

public struct AdapterScanView: View {
    public var vehicleData: VehicleDataManager

    private var bluetoothManager: BluetoothManager? {
        vehicleData.obdConnection as? BluetoothManager
    }

    public var body: some View {
        List {
            Section("Status & Actions") {
                HStack {
                    Text("Connection Status")
                    Spacer()
                    Text(statusText)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(statusColor)
                }

                if vehicleData.connectionState.isConnected {
                    Button(role: .destructive) {
                        vehicleData.obdConnection.disconnect()
                    } label: {
                        HStack {
                            Image(systemName: "power")
                            Text("Disconnect Adapter")
                        }
                    }
                } else {
                    Button {
                        if case .scanning = vehicleData.connectionState {
                            vehicleData.obdConnection.disconnect()
                        } else {
                            vehicleData.obdConnection.connect(peripheralName: nil)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isScanning ? "stop.fill" : "antenna.radiowaves.left.and.right")
                            Text(isScanning ? "Stop Scanning" : "Scan for Nearby BLE Adapters")
                        }
                    }
                }
            }

            Section("Discovered BLE Devices") {
                if let devices = bluetoothManager?.discoveredDevices, !devices.isEmpty {
                    ForEach(devices, id: \.identifier) { device in
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundStyle(Theme.electricCyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name ?? "Unnamed Device")
                                    .font(.headline)
                                Text(device.identifier.uuidString)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button("Connect") {
                                bluetoothManager?.connect(to: device)
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        }
                    }
                } else if isScanning {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Searching for OBD-II BLE adapters...")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Text("No devices found yet. Tap scan above to search for nearby OBD-II Bluetooth adapters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("BLE Scanner")
        .onAppear {
            if !vehicleData.isDemoMode && !vehicleData.connectionState.isConnected {
                vehicleData.obdConnection.connect(peripheralName: nil)
            }
        }
    }

    private var isScanning: Bool {
        if case .scanning = vehicleData.connectionState {
            return true
        }
        return false
    }

    private var statusText: String {
        switch vehicleData.connectionState {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting(let dev): return "Connecting to \(dev)..."
        case .ready(let dev): return "Connected (\(dev))"
        case .demoMode: return "Demo / Simulation Mode"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch vehicleData.connectionState {
        case .ready, .demoMode: return .green
        case .connecting, .scanning: return .orange
        case .disconnected: return .secondary
        case .error: return .red
        }
    }
}

private struct SOCReferenceSettingsView: View {
    var vehicleData: VehicleDataManager
    @State private var dashboardSOC = ""
    @State private var referenceError: String?
    @FocusState private var isInputFocused: Bool

    private var referenceValue: Double? {
        let text = dashboardSOC.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(text), value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let isLive = vehicleData.canSetSOCReference()
                    let reported =
                        vehicleData.latestTelemetry.stateOfChargePct
                        .formatted(.number.precision(.fractionLength(1))) + "%"
                    let adjusted =
                        vehicleData.displayedTelemetry.stateOfChargePct
                        .formatted(.number.precision(.fractionLength(1))) + "%"
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("OBD-reported SOC", value: isLive ? reported : "Unavailable")
                        LabeledContent("Adjusted SOC", value: isLive ? adjusted : "Unavailable")
                        if !isLive {
                            Text("Connect to your car with a profile that supplies live SOC. A reading from the last 15 seconds is required.")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                TextField("Car dashboard SOC (%)", text: $dashboardSOC)
                    #if os(iOS)
                .keyboardType(.decimalPad)
                    #endif
                    .focused($isInputFocused)
                    .accessibilityLabel("Car dashboard SOC, percent")
                    .onChange(of: dashboardSOC) { _, _ in referenceError = nil }

                if !dashboardSOC.isEmpty && referenceValue == nil {
                    Text("Enter a number from 0 to 100.")
                        .font(.caption)
                        .foregroundStyle(Theme.criticalRed)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Button("Use as Reference") {
                        guard let value = referenceValue, vehicleData.setSOCReference(value) else {
                            referenceError = "Wait for a fresh SOC reading, then try again."
                            return
                        }
                        referenceError = nil
                        dashboardSOC = ""
                        isInputFocused = false
                    }
                    .disabled(referenceValue == nil || !vehicleData.canSetSOCReference())
                }

                if let referenceError {
                    Text(referenceError)
                        .font(.caption)
                        .foregroundStyle(Theme.criticalRed)
                }

                if let offset = vehicleData.socReferenceOffset {
                    LabeledContent("Saved adjustment", value: String(format: "%+.1f percentage points", offset))
                    Button("Reset SOC Reference") {
                        vehicleData.resetSOCReference()
                        referenceError = nil
                    }
                }
            } header: {
                Text("SOC Reference")
            } footer: {
                Text(
                    "Enter the percentage currently shown by your car. VoltLink saves the difference for this vehicle, model year and profile, then adjusts live displays and charging-target estimates. Original readings are kept for recordings and charging-power calculations. The adjustment is not applied in Demo Mode."
                )
            }
        }
        .navigationTitle("SOC Reference")
        .inlineTitleDisplayMode()
    }
}

#Preview("Settings View") {
    SettingsView(
        vehicleData: VehicleDataManager(),
        tripTracker: TripTrackingManager()
    )
}
