import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var vehicleData: VehicleDataManager
    @State private var selectedUnitIndex = 0

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
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

                Section("Vehicle Profile") {
                    HStack {
                        Text("Active Profile")
                        Spacer()
                        Text(vehicleData.selectedProfile.vehicleName)
                            .foregroundColor(.gray)
                    }
                }

                Section("Bluetooth Adapter") {
                    NavigationLink("Scan Nearby BLE Devices") {
                        AdapterScanView(vehicleData: vehicleData)
                    }
                }

                Section("App Information") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text("1.0.0 (VoltLink EQA)")
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
                    Text("Signal Strong")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
            }
        }
        .navigationTitle("BLE Scanner")
    }
}
