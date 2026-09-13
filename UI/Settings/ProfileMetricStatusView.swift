import SwiftUI

/// Shows, for the currently selected vehicle profile, which telemetry metrics
/// it claims to support and whether each one is currently arriving live over
/// the polling loop.
public struct ProfileMetricStatusView: View {
    @ObservedObject public var vehicleData: VehicleDataManager

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var metrics: [TelemetryMetric] {
        TelemetryMetric.allCases.filter { vehicleData.supportedMetrics.contains($0) }
    }

    public var body: some View {
        List {
            if vehicleData.selectedProfileID == .mercedesEQAOBDb {
                Section("OBDb community profile") {
                    Text("Experimental definitions: compare readings with your car. Charging assumes negative pack current means charging and requires fresh stationary wheel speed. Coolant temperature is not battery-cell temperature.")
                    Link("Source: OBDb / Mercedes-Benz EQA contributors", destination: MercedesEQAOBDbProfile.sourceURL)
                    Link("Adapted under CC BY-SA 4.0", destination: MercedesEQAOBDbProfile.licenseURL)
                    Text("Adapted to Swift with explicit adapter routing and validity checks. Provided as-is, without warranties.")
                        .font(.caption)
                }
            }
            Section {
                ForEach(metrics) { metric in
                    HStack {
                        Image(systemName: metric.sfSymbolName)
                            .foregroundColor(Theme.electricCyan)
                            .frame(width: 24)

                        Text(metric.displayName)
                            .foregroundColor(Theme.textPrimary)

                        Spacer()

                        statusLabel(for: metric)
                    }
                }
            } header: {
                Text("\(vehicleData.vehicleName) — \(metrics.count) metrics")
            } footer: {
                Text("\"Live\" means this metric arrived in the most recent poll cycle. A metric drops back to \"No data\" after 3 consecutive failed polls for its command.")
            }
        }
        .navigationTitle("Profile Metric Status")
        .inlineTitleDisplayMode()
    }

    @ViewBuilder
    private func statusLabel(for metric: TelemetryMetric) -> some View {
        if vehicleData.liveMetrics.contains(metric) {
            Text("Live")
                .font(.caption)
                .bold()
                .foregroundColor(Theme.regenGreen)
        } else if vehicleData.connectionState.isConnected || vehicleData.isDemoMode {
            Text("No data")
                .font(.caption)
                .foregroundColor(Theme.highPowerAmber)
        } else {
            Text("Not connected")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }
}

#Preview("Profile Metric Status") {
    NavigationStack {
        ProfileMetricStatusView(vehicleData: VehicleDataManager())
    }
}
