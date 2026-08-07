import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @ObservedObject public var tripTracker: TripTrackingManager

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

                Section("Vehicle Profile") {
                    Picker("Active Profile", selection: Binding(
                        get: { vehicleData.selectedProfileID },
                        set: { vehicleData.selectProfile($0) }
                    )) {
                        ForEach(VehicleProfileID.allCases) { id in
                            Text(id.displayName).tag(id)
                        }
                    }
                }

                Section("Bluetooth Adapter") {
                    NavigationLink("Scan Nearby BLE Devices") {
                        AdapterScanView(vehicleData: vehicleData)
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
        }
    }
}

public struct AdapterScanView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

    public var body: some View {
        List {
            Section("Available OBD-II Bluetooth Adapters") {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("Vgate iCar Pro 2S (BLE)")
                            .font(.headline)
                        Text("IOS-Vlink-18F0")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text(vehicleData.connectionState.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(vehicleData.connectionState.isConnected ? .green : .cyan)
                }
            }
        }
        .navigationTitle("BLE Scanner")
    }
}
