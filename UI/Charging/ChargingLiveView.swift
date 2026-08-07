import SwiftUI

public struct ChargingLiveView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var isConnected: Bool {
        vehicleData.isDemoMode || vehicleData.connectionState.isConnected
    }

    private var isCharging: Bool {
        isConnected && (vehicleData.latestTelemetry.isCharging || vehicleData.latestTelemetry.chargePowerKW > 0)
    }

    private var usableCapacityKWh: Double {
        vehicleData.selectedProfile.batteryUsableCapacityKWh
    }

    private var storedEnergyKWh: Double {
        usableCapacityKWh * (vehicleData.latestTelemetry.stateOfChargePct / 100.0)
    }

    private var energyNeededToFullKWh: Double {
        usableCapacityKWh * ((100.0 - vehicleData.latestTelemetry.stateOfChargePct) / 100.0)
    }

    private var timeTo80Min: Int {
        guard isConnected else { return 0 }
        let remainingPct = max(0, 80.0 - vehicleData.latestTelemetry.stateOfChargePct)
        let neededKWh = (remainingPct / 100.0) * usableCapacityKWh
        let rate = max(10.0, vehicleData.latestTelemetry.chargePowerKW)
        return Int((neededKWh / rate) * 60.0)
    }

    private var timeTo100Min: Int {
        guard isConnected else { return 0 }
        let remainingPct = max(0, 100.0 - vehicleData.latestTelemetry.stateOfChargePct)
        let neededKWh = (remainingPct / 100.0) * usableCapacityKWh
        let rate = max(10.0, vehicleData.latestTelemetry.chargePowerKW)
        return Int((neededKWh / rate) * 60.0)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Scanner Connection Disconnected Banner
                        if !isConnected {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Theme.highPowerAmber)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("OBD SCANNER DISCONNECTED")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.highPowerAmber)
                                    Text("Connect to a Bluetooth scanner in Settings or turn on Demo Mode to stream live charging data.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Theme.highPowerAmber.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.highPowerAmber.opacity(0.4), lineWidth: 1)
                            )
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Charging Header Status
                        VStack(spacing: 8) {
                            Image(systemName: isCharging ? "bolt.batteryblock.fill" : "batteryblock")
                                .font(.system(size: 60))
                                .foregroundColor(isCharging ? Theme.regenGreen : (isConnected ? Theme.electricCyan : Theme.textSecondary))
                                .symbolEffect(.bounce, value: isCharging)

                            Text(isCharging ? "FAST CHARGING ACTIVE" : (isConnected ? "NOT CHARGING" : "SCANNER DISCONNECTED"))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(isCharging ? Theme.regenGreen : Theme.textSecondary)

                            Text(isConnected ? String(format: "%.1f kW", vehicleData.latestTelemetry.chargePowerKW) : "-- kW")
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .glassCard()
                        .padding(.horizontal)

                        // Battery State of Charge Ring
                        BatteryLevelBar(
                            socPct: isConnected ? vehicleData.latestTelemetry.stateOfChargePct : 0.0,
                            batteryTempC: isConnected ? vehicleData.latestTelemetry.batteryTempC : 0.0,
                            isCharging: isCharging
                        )
                        .padding(.horizontal)

                        // Battery Specifications & Usable Capacity Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("BATTERY SPECIFICATIONS & CAPACITY")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal)

                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Usable Capacity")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(String(format: "%.1f kWh", usableCapacityKWh))
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.electricCyan)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Current Stored Energy")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(isConnected ? String(format: "%.1f kWh", storedEnergyKWh) : "-- kWh")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.textPrimary)
                                    }
                                }

                                Divider().background(Color.white.opacity(0.1))

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Energy Needed to 100%")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(isConnected ? String(format: "%.1f kWh", energyNeededToFullKWh) : "-- kWh")
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.highPowerAmber)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Vehicle Profile")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(vehicleData.selectedProfile.vehicleName)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding()
                            .glassCard()
                            .padding(.horizontal)
                        }

                        // Time to 80% / 100% Countdown & Health
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ESTIMATED TO 80%")
                                    .font(.caption).fontWeight(.bold).foregroundColor(Theme.textSecondary)
                                Text(isCharging ? "\(timeTo80Min) min" : "--")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("BATTERY SOH HEALTH")
                                    .font(.caption).fontWeight(.bold).foregroundColor(Theme.textSecondary)
                                Text(isConnected ? String(format: "%.1f%%", vehicleData.latestTelemetry.stateOfHealthPct) : "--%")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.regenGreen)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                        }
                        .padding(.horizontal)

                        if vehicleData.isDemoMode {
                            Button {
                                if let mock = vehicleData.obdConnection as? MockOBDAdapter {
                                    mock.simulationEngine.scenario = .dcFastCharging
                                }
                            } label: {
                                Label("Simulate DC Fast Charging (100 kW)", systemImage: "bolt.fill")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.regenGreen)
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Charge & Health")
            .inlineTitleDisplayMode()
        }
    }
}
