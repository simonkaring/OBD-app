import SwiftUI

public struct ChargingLiveView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var isCharging: Bool {
        vehicleData.latestTelemetry.isCharging || vehicleData.latestTelemetry.chargePowerKW > 0
    }

    private var timeTo80Min: Int {
        let remainingPct = max(0, 80.0 - vehicleData.latestTelemetry.stateOfChargePct)
        let neededKWh = (remainingPct / 100.0) * 66.5
        let rate = max(10.0, vehicleData.latestTelemetry.chargePowerKW)
        return Int((neededKWh / rate) * 60.0)
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
                                .foregroundColor(isCharging ? Theme.regenGreen : Theme.electricCyan)
                                .symbolEffect(.bounce, value: isCharging)

                            Text(isCharging ? "FAST CHARGING ACTIVE" : "NOT CHARGING")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(isCharging ? Theme.regenGreen : Theme.textSecondary)

                            Text(String(format: "%.1f kW", vehicleData.latestTelemetry.chargePowerKW))
                                .font(.system(size: 48, weight: .black, design: .rounded))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .glassCard()
                        .padding(.horizontal)

                        // Battery State of Charge Ring
                        BatteryLevelBar(
                            socPct: vehicleData.latestTelemetry.stateOfChargePct,
                            batteryTempC: vehicleData.latestTelemetry.batteryTempC,
                            isCharging: isCharging
                        )
                        .padding(.horizontal)

                        // Time to 80% / 100% Countdown
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ESTIMATED TIME TO 80%")
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
                                Text(String(format: "%.1f%%", vehicleData.latestTelemetry.stateOfHealthPct))
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
