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
        hasChargePower && (vehicleData.latestTelemetry.isCharging || vehicleData.latestTelemetry.chargePowerKW > 0)
    }

    private var hasSOC: Bool {
        vehicleData.isDemoMode || vehicleData.latestTelemetry.socUpdatedAt != nil
    }

    private var hasChargePower: Bool {
        vehicleData.isDemoMode || vehicleData.latestTelemetry.chargePowerUpdatedAt != nil
    }

    private var chargingStatusText: String {
        if !isConnected {
            return "SCANNER DISCONNECTED"
        }
        if !hasChargePower {
            return "CHARGE DATA UNAVAILABLE"
        }
        if !isCharging {
            return "NOT CHARGING"
        }
        return "CHARGING"
    }

    private var usableCapacityKWh: Double {
        vehicleData.usableBatteryCapacityKWh
    }

    private var storedEnergyKWh: Double {
        usableCapacityKWh * (vehicleData.latestTelemetry.stateOfChargePct / 100.0)
    }

    private var energyNeededToFullKWh: Double {
        usableCapacityKWh * ((100.0 - vehicleData.latestTelemetry.stateOfChargePct) / 100.0)
    }

    private var timeTo80Min: Int {
        guard isConnected && hasSOC && isCharging else { return 0 }
        let remainingPct = max(0, 80.0 - vehicleData.latestTelemetry.stateOfChargePct)
        guard remainingPct > 0 else { return 0 }
        let neededKWh = (remainingPct / 100.0) * usableCapacityKWh
        return Int((neededKWh / vehicleData.latestTelemetry.chargePowerKW) * 60.0)
    }

    private var timeTo100Min: Int {
        guard isConnected && hasSOC && isCharging else { return 0 }
        let remainingPct = max(0, 100.0 - vehicleData.latestTelemetry.stateOfChargePct)
        guard remainingPct > 0 else { return 0 }
        let neededKWh = (remainingPct / 100.0) * usableCapacityKWh
        return Int((neededKWh / vehicleData.latestTelemetry.chargePowerKW) * 60.0)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Charging Header Status
                        VStack(spacing: 8) {
                            Image(systemName: isCharging ? "bolt.batteryblock.fill" : "batteryblock")
                                .font(.system(size: 60))
                                .foregroundColor(isCharging ? Theme.regenGreen : (isConnected ? Theme.electricCyan : Theme.textSecondary))
                                .symbolEffect(.bounce, value: isCharging)

                            Text(chargingStatusText)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(isCharging ? Theme.regenGreen : Theme.textSecondary)

                            Text(hasChargePower ? String(format: "%.1f kW", vehicleData.latestTelemetry.chargePowerKW) : "— kW")
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .foregroundColor(isCharging ? Theme.regenGreen : Theme.textPrimary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .glassCard()
                        .padding(.horizontal)

                        // Battery State of Charge Ring
                        BatteryLevelBar(
                            socPct: hasSOC ? vehicleData.latestTelemetry.stateOfChargePct : nil,
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
                                        Text(hasSOC ? String(format: "%.1f kWh", storedEnergyKWh) : "— kWh")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.textPrimary)
                                    }
                                }

                                Divider().background(Color.white.opacity(0.1))

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Energy Needed to 100%")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(hasSOC ? String(format: "%.1f kWh", energyNeededToFullKWh) : "— kWh")
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.highPowerAmber)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Vehicle Profile")
                                            .font(.caption).foregroundColor(Theme.textSecondary)
                                        Text(vehicleData.vehicleName)
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
                                Text(hasSOC && isCharging ? "\(timeTo80Min) min" : "—")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.electricCyan)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("BATTERY SOH HEALTH")
                                    .font(.caption).fontWeight(.bold).foregroundColor(Theme.textSecondary)
                                Text(isConnected && vehicleData.latestTelemetry.stateOfHealthPct > 0 ? String(format: "%.1f%%", vehicleData.latestTelemetry.stateOfHealthPct) : "--%")
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

#Preview("Charging Live View") {
    ChargingLiveView(
        vehicleData: VehicleDataManager()
    )
}
