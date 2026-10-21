import SwiftUI

public struct ChargingLiveView: View {
    public var vehicleData: VehicleDataManager

    /// Scales the headline kW readout with the user's Dynamic Type setting.
    @ScaledMetric(relativeTo: .largeTitle) private var powerFontSize: CGFloat = 48

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
        isConnected
            && TelemetryMetric.soc.isAvailable(in: vehicleData.latestTelemetry, liveMetrics: vehicleData.liveMetrics, isDemoMode: vehicleData.isDemoMode)
    }

    private var hasChargePower: Bool {
        isConnected && vehicleData.hasChargePower
    }

    private var hasBatteryTemperature: Bool {
        vehicleData.isDemoMode || vehicleData.liveMetrics.contains(.batteryTemp)
    }

    private var chargingStatusText: String {
        if !isConnected {
            return "Scanner disconnected"
        }
        if !hasChargePower {
            return "Charge data unavailable"
        }
        if !isCharging {
            return "Not charging"
        }
        return vehicleData.latestTelemetry.chargePowerSource == .socEstimate ? "Charging (estimated)" : "Charging"
    }

    /// Battery level when the current charge began, on the same scale as the displayed level
    /// (a saved dashboard reference offset applies to both). Only shown while charging.
    private var chargingStartSocPct: Double? {
        guard isCharging, hasSOC, let startSoc = vehicleData.chargingSession.startSOC,
            startSoc.isFinite, startSoc >= 0
        else { return nil }
        let displayedStart = vehicleData.displayedSOC(fromRaw: startSoc)
        guard displayedStart <= vehicleData.displayedTelemetry.stateOfChargePct else { return nil }
        return displayedStart
    }

    private var usableCapacityKWh: Double {
        vehicleData.usableBatteryCapacityKWh
    }

    private var hasCapacity: Bool { usableCapacityKWh.isFinite && usableCapacityKWh > 0 }

    private var storedEnergyKWh: Double {
        usableCapacityKWh * (vehicleData.displayedTelemetry.stateOfChargePct / 100.0)
    }

    private var energyNeededToFullKWh: Double {
        usableCapacityKWh * ((100.0 - vehicleData.displayedTelemetry.stateOfChargePct) / 100.0)
    }

    private func minutesToTarget(_ targetPct: Double) -> Int {
        guard isConnected && hasSOC && isCharging && hasCapacity else { return 0 }
        let remainingPct = max(0, targetPct - vehicleData.displayedTelemetry.stateOfChargePct)
        // `isCharging` can be true from a status bit while the reported rate is still 0 kW
        // (profile reports charging without a power reading, or the charger is handshaking).
        // Dividing by it traps on `Int(inf)`, so require a real rate first.
        let powerKW = vehicleData.latestTelemetry.chargePowerKW
        guard remainingPct > 0, powerKW > 0 else { return 0 }
        let neededKWh = (remainingPct / 100.0) * usableCapacityKWh
        return Int((neededKWh / powerKW) * 60.0)
    }

    private var timeTo80Min: Int { minutesToTarget(80.0) }

    private var timeTo100Min: Int { minutesToTarget(100.0) }

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
                                .foregroundStyle(isCharging ? Theme.regenGreen : (isConnected ? Theme.electricCyan : Theme.textSecondary))
                                .symbolEffect(.bounce, value: isCharging)

                            Text(chargingStatusText)
                                .font(.headline)
                                .foregroundStyle(isCharging ? Theme.regenGreen : Theme.textSecondary)

                            Text(
                                hasChargePower
                                    ? UnitPreferences.shared.power(kilowatts: vehicleData.latestTelemetry.chargePowerKW)
                                    : "— \(UnitPreferences.shared.powerUnit.symbol)"
                            )
                            .font(.system(size: powerFontSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isCharging ? Theme.regenGreen : Theme.textPrimary)

                            if vehicleData.latestTelemetry.chargePowerSource == .socEstimate {
                                Text("Estimated from battery level change, not AC wall power.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .glassCard()
                        .padding(.horizontal)

                        // Battery State of Charge Ring
                        BatteryLevelBar(
                            socPct: hasSOC ? vehicleData.displayedTelemetry.stateOfChargePct : nil,
                            batteryTempC: isConnected && hasBatteryTemperature ? vehicleData.latestTelemetry.batteryTempC : nil,
                            isCharging: isCharging,
                            startSocPct: chargingStartSocPct
                        )
                        .padding(.horizontal)

                        // Battery Specifications & Usable Capacity Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Battery capacity")
                                .font(.headline)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal)

                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Usable Capacity")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                        Text(hasCapacity ? UnitPreferences.shared.energy(kilowattHours: usableCapacityKWh, decimals: 1) : "Unknown")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Current Stored Energy")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                        Text(
                                            hasSOC && hasCapacity
                                                ? UnitPreferences.shared.energy(kilowattHours: storedEnergyKWh, decimals: 1)
                                                : "— kWh"
                                        )
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    }
                                }

                                Divider().background(Theme.divider)

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Energy Needed to 100%")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                        Text(
                                            hasSOC && hasCapacity
                                                ? UnitPreferences.shared.energy(kilowattHours: energyNeededToFullKWh, decimals: 1)
                                                : "— kWh"
                                        )
                                        .font(.headline)
                                        .foregroundStyle(Theme.highPowerAmber)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Vehicle Profile")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                        Text(vehicleData.vehicleName)
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.textSecondary)
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
                                Text("Estimated to 80%")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(hasSOC && isCharging && hasCapacity ? "\(timeTo80Min) min" : "—")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Battery health")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(
                                    isConnected && vehicleData.latestTelemetry.stateOfHealthPct > 0
                                        ? String(format: "%.1f%%", vehicleData.latestTelemetry.stateOfHealthPct) : "--%"
                                )
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.regenGreen)
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
                                    .font(.subheadline.weight(.semibold))
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.regenGreen)
                                    .foregroundStyle(Theme.onAccent)
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
