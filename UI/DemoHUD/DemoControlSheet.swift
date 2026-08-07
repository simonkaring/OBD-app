import SwiftUI

public struct DemoControlSheet: View {
    @ObservedObject public var simulationEngine: MockDrivingSimulation
    @Environment(\.dismiss) private var dismiss

    @State private var targetSpeed: Double = 50.0
    @State private var regenLevel: Double = 0.5

    public init(simulationEngine: MockDrivingSimulation) {
        self.simulationEngine = simulationEngine
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Preset Simulation Scenario") {
                    Picker("Scenario", selection: $simulationEngine.scenario) {
                        ForEach(DemoScenario.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Manual Drive Controls") {
                    VStack(alignment: .leading) {
                        Text("Simulated Speed: \(Int(targetSpeed)) km/h")
                        Slider(value: $targetSpeed, in: 0...160, step: 5) { _ in
                            simulationEngine.userSpeedOverride = targetSpeed
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Regen Braking Force: \(Int(regenLevel * 100))%")
                        Slider(value: $regenLevel, in: 0...1.0) { _ in
                            simulationEngine.userRegenOverride = regenLevel
                        }
                    }

                    Button("Reset Manual Overrides") {
                        simulationEngine.userSpeedOverride = nil
                        simulationEngine.userThrottleOverride = nil
                        simulationEngine.userRegenOverride = nil
                    }
                    .foregroundColor(.cyan)
                }

                Section("Diagnostic Fault Injection") {
                    Button("Inject Test DTC Code (P0A80)") {
                        simulationEngine.scenario = .faultInjection
                        simulationEngine.injectedFaultCode = "P0A80"
                    }
                    .foregroundColor(.orange)

                    Button("Clear Test Fault Codes") {
                        simulationEngine.injectedFaultCode = nil
                        simulationEngine.scenario = .cityDriving
                    }
                    .foregroundColor(.green)
                }
            }
            .navigationTitle("Demo Controls")
            .inlineTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
