import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#endif

public struct SettingsView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @ObservedObject public var tripTracker: TripTrackingManager

    @State private var showVehiclePicker = false

    @AppStorage("developerModeEnabled") private var developerModeEnabled: Bool = false
    @AppStorage("aiApiKey") private var aiApiKey: String = ""

    @State private var targetSpeed: Double = 50.0
    @State private var regenLevel: Double = 0.5

    public init(vehicleData: VehicleDataManager, tripTracker: TripTrackingManager = AppEnvironment.shared.tripTracker) {
        self.vehicleData = vehicleData
        self.tripTracker = tripTracker
    }

    private var mockEngine: MockDrivingSimulation? {
        (vehicleData.obdConnection as? MockOBDAdapter)?.simulationEngine
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Mode Selection") {
                    Toggle("Demo / Simulation Mode", isOn: Binding(
                        get: { vehicleData.isDemoMode },
                        set: { vehicleData.toggleDemoMode($0) }
                    ))
                }

                if vehicleData.isDemoMode, let engine = mockEngine {
                    Section("Demo Simulation Controls") {
                        Picker("Preset Scenario", selection: Binding(
                            get: { engine.scenario },
                            set: { engine.scenario = $0 }
                        )) {
                            ForEach(DemoScenario.allCases) { scenario in
                                Text(scenario.rawValue).tag(scenario)
                            }
                        }
                        .pickerStyle(.menu)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Simulated Speed: \(Int(targetSpeed)) km/h")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Slider(value: $targetSpeed, in: 0...160, step: 5) { _ in
                                engine.userSpeedOverride = targetSpeed
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Regen Braking Force: \(Int(regenLevel * 100))%")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        .foregroundColor(Theme.electricCyan)

                        HStack {
                            Button("Inject DTC Fault (P0A80)") {
                                engine.scenario = .faultInjection
                                engine.injectedFaultCode = "P0A80"
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)

                            Spacer()

                            Button("Clear Fault Codes") {
                                engine.injectedFaultCode = nil
                                engine.scenario = .cityDriving
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        }
                    }
                }

                Section("Trip Recording Automation") {
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
                }

                Section("GPS Route Recording") {
                    switch tripTracker.locationAuthorizationStatus {
                    case .notDetermined:
                        Button("Enable GPS Route Recording", systemImage: "location") {
                            tripTracker.requestLocationAuthorization()
                        }
                        Text("Allow location while using VoltLink to save routes with your trips.")
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

                Section("Vehicle Profile") {
                    Button {
                        showVehiclePicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active Vehicle")
                                    .font(.body)
                                    .foregroundColor(Theme.textPrimary)
                                Text(vehicleData.vehicleName)
                                    .font(.caption)
                                    .foregroundColor(Theme.electricCyan)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }

                    if vehicleData.isCalibrating {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Calibrating profile metrics...")
                                    .font(.subheadline)
                                    .foregroundColor(Theme.electricCyan)
                                Spacer()
                                Text("\(Int(vehicleData.calibrationProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
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
                                Label(vehicleData.calibratedCommands == nil ? "Calibrate Live Metrics" : "Re-calibrate Metrics", systemImage: "slider.horizontal.3")
                                    .foregroundColor(vehicleData.connectionState.isConnected ? Theme.electricCyan : .secondary)
                            }
                            .disabled(!vehicleData.connectionState.isConnected)

                            Spacer()

                            if let summary = vehicleData.calibrationSummary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundColor(Theme.regenGreen)

                                Button {
                                    vehicleData.resetCalibration()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !vehicleData.connectionState.isConnected {
                            Text("Connect to your OBD adapter or enable Demo Mode to run metric calibration.")
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }

                Section("Bluetooth Adapter") {
                    NavigationLink("Scan Nearby BLE Devices") {
                        AdapterScanView(vehicleData: vehicleData)
                    }
                }

                Section("Developer & Reverse Engineering") {
                    Toggle("Developer Mode", isOn: $developerModeEnabled)

                    if developerModeEnabled {
                        NavigationLink("OBD Terminal & AI Discovery") {
                            OBDTerminalView(vehicleData: vehicleData)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI API Key (Optional)")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                            SecureField("Gemini or OpenAI API Key", text: $aiApiKey)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }

                        Text("Supports Google Gemini or OpenAI API keys stored locally on-device. If left blank, you can still export formatted traces for AI using the Share button.")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Section("CarPlay") {
                    NavigationLink("CarPlay Tiles") {
                        CarPlayTileEditorView(vehicleData: vehicleData)
                    }
                }

                Section("App Information") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .inlineTitleDisplayMode()
            .sheet(isPresented: $showVehiclePicker) {
                VehicleProfilePickerSheet(vehicleData: vehicleData)
            }
        }
    }
}

public struct AdapterScanView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

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
                        .foregroundColor(statusColor)
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
                                .foregroundColor(Theme.electricCyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name ?? "Unnamed Device")
                                    .font(.headline)
                                Text(device.identifier.uuidString)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
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
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    Text("No devices found yet. Tap scan above to search for nearby OBD-II Bluetooth adapters.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

#Preview("Settings View") {
    SettingsView(
        vehicleData: VehicleDataManager(),
        tripTracker: TripTrackingManager()
    )
}
