import SwiftUI

public struct ChargingLiveView: View {
    public var vehicleData: VehicleDataManager

    /// Scales the headline kW readout with the user's Dynamic Type setting.
    @ScaledMetric(relativeTo: .largeTitle) private var powerFontSize: CGFloat = 48
    @AppStorage(ChargingTarget.socKey) private var storedChargeTarget = ChargingTarget.defaultSOC

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

    /// The stored target, ignoring a value written by an older build outside the options.
    private var chargeTarget: Double {
        ChargingTarget.options.contains(storedChargeTarget) ? storedChargeTarget : ChargingTarget.defaultSOC
    }

    /// Remaining charge time, integrated over 1% bands so the DC taper above 80% is included.
    private func estimatedSeconds(to targetPct: Double) -> TimeInterval? {
        guard isConnected && hasSOC && isCharging && hasCapacity else { return nil }
        return ChargingTimeEstimator.secondsToTarget(
            currentSOC: vehicleData.displayedTelemetry.stateOfChargePct,
            targetSOC: targetPct,
            currentPowerKW: vehicleData.latestTelemetry.chargePowerKW,
            capacityKWh: usableCapacityKWh,
            observedCurve: vehicleData.chargingSession.history.map {
                ChargingCurveSample(socPct: $0.soc, powerKW: $0.powerKW)
            })
    }

    private func estimateLabel(_ targetPct: Double) -> String {
        guard let seconds = estimatedSeconds(to: targetPct) else { return "—" }
        return seconds <= 0 ? "Reached" : ChargingSessionSummary.duration(seconds)
    }

    private var targetEstimateLabel: String { estimateLabel(chargeTarget) }

    private var fullChargeEstimateLabel: String { estimateLabel(100.0) }

    /// Start of the live charging session, which drives the elapsed and average readouts.
    private var chargingStartedAt: Date? {
        vehicleData.chargingSession.startTime
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

                            if isCharging {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let elapsed = chargingStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
                                    HStack(spacing: 28) {
                                        VStack(spacing: 2) {
                                            Text("Elapsed")
                                                .font(.caption)
                                                .foregroundStyle(Theme.textSecondary)
                                            Text(ChargingSessionSummary.duration(elapsed))
                                                .font(.subheadline.weight(.semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(Theme.textPrimary)
                                        }

                                        VStack(spacing: 2) {
                                            Text("Avg speed")
                                                .font(.caption)
                                                .foregroundStyle(Theme.textSecondary)
                                            Text(
                                                ChargingSessionSummary.averagePowerKW(
                                                    energyKWh: vehicleData.chargingSession.totalEnergyKWh,
                                                    over: elapsed
                                                ).map { UnitPreferences.shared.power(kilowatts: $0) } ?? "—"
                                            )
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.textPrimary)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }

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

                        // Charging Speed Curve
                        if isCharging {
                            let speedCurve = ChargingSpeedCurve.live(vehicleData.chargingSession.history)
                            if speedCurve.count > 1 {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Charging speed")
                                        .font(.headline)
                                        .foregroundStyle(Theme.textSecondary)

                                    ChargingSpeedChart(points: speedCurve)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard()
                                .padding(.horizontal)
                            }
                        }

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

                        // Time to target / full & battery health
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Estimate to \(Int(chargeTarget))%")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Menu {
                                        ForEach(ChargingTarget.options, id: \.self) { option in
                                            Button {
                                                storedChargeTarget = option
                                            } label: {
                                                if option == chargeTarget {
                                                    Label("\(Int(option))%", systemImage: "checkmark")
                                                } else {
                                                    Text("\(Int(option))%")
                                                }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.caption)
                                            .foregroundStyle(Theme.electricCyan)
                                    }
                                    .accessibilityLabel("Change charge target")
                                }
                                Text(targetEstimateLabel)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Estimate to 100%")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(fullChargeEstimateLabel)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                        }
                        .padding(.horizontal)

                        NavigationLink {
                            BatteryHealthView(vehicleData: vehicleData)
                        } label: {
                            HStack {
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
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
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
