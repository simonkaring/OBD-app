import Charts
import SwiftData
import SwiftUI

/// State-of-health history for the active vehicle, charted from the daily samples that
/// `BatteryHealthRecorder` stores while the adapter is connected.
public struct BatteryHealthView: View {
    public var vehicleData: VehicleDataManager

    @Query(sort: \BatteryHealthSampleModel.recordedAt) private var allSamples: [BatteryHealthSampleModel]

    public init(vehicleData: VehicleDataManager) {
        self.vehicleData = vehicleData
    }

    private var samples: [BatteryHealthSampleModel] {
        allSamples.filter { $0.vehicleName == vehicleData.vehicleName && $0.sohPct.isFinite }
    }

    private var trend: BatteryHealthTrend? {
        BatteryHealthTrend.summarize(
            points: samples.map { BatteryHealthPoint(date: $0.recordedAt, sohPct: $0.sohPct) })
    }

    private var liveSOH: Double? {
        guard vehicleData.isDemoMode || vehicleData.connectionState.isConnected,
            vehicleData.liveMetrics.contains(.soh),
            vehicleData.latestTelemetry.stateOfHealthPct.isFinite,
            vehicleData.latestTelemetry.stateOfHealthPct > 0
        else { return nil }
        return vehicleData.latestTelemetry.stateOfHealthPct
    }

    private var latestSOH: Double? {
        liveSOH ?? samples.last?.sohPct
    }

    /// Pads the chart domain so a flat or slightly noisy history is not magnified into a
    /// dramatic-looking cliff.
    private var chartDomain: ClosedRange<Double> {
        let values = samples.map(\.sohPct)
        guard let low = values.min(), let high = values.max() else { return 80...100 }
        let padding = max(1.0, (high - low) * 0.2)
        return max(0, low - padding)...min(100, high + padding)
    }

    public var body: some View {
        ZStack {
            Theme.backgroundDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    if let trend {
                        summaryGrid(trend)
                    }

                    if samples.count >= 2 {
                        chart
                    } else {
                        emptyState
                    }

                    Text(
                        "One reading is kept per day while the adapter is connected; later readings replace that day's value. \"Recorded distance\" only counts drives logged in VoltLink, not the vehicle odometer. State of health is reported by the battery ECU, so its precision depends on the active vehicle profile."
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Battery Health")
        .inlineTitleDisplayMode()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.regenGreen)

            Text(latestSOH.map { String(format: "%.1f%%", $0) } ?? "--%")
                .font(.system(size: 52, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

            Text(liveSOH != nil ? "Live state of health" : (samples.isEmpty ? "No readings yet" : "Latest stored reading"))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Text(vehicleData.vehicleName)
                .font(.caption)
                .foregroundStyle(Theme.electricCyan)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassCard()
        .padding(.horizontal)
    }

    private func summaryGrid(_ trend: BatteryHealthTrend) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat(
                title: "Since first reading",
                value: String(format: "%+.1f pp", trend.changePct),
                subtitle: String(format: "%.1f%% → %.1f%%", trend.firstSohPct, trend.latestSohPct),
                accent: trend.changePct < 0 ? Theme.highPowerAmber : Theme.regenGreen)

            stat(
                title: "Estimated per year",
                value: trend.annualizedChangePct.map { String(format: "%+.1f pp", $0) } ?? "—",
                subtitle: trend.annualizedChangePct == nil
                    ? "Needs two weeks of readings" : "Straight-line projection",
                accent: Theme.electricCyan)

            stat(
                title: "Readings",
                value: "\(trend.sampleCount)",
                subtitle: String(format: "%.0f days observed", trend.observedDays.rounded()),
                accent: Theme.textPrimary)

            stat(
                title: "Recorded distance",
                value: samples.last.map {
                    UnitPreferences.shared.distance(kilometers: $0.recordedDistanceKm, decimals: 0)
                } ?? "—",
                subtitle: "Trips logged in VoltLink",
                accent: Theme.textPrimary)
        }
        .padding(.horizontal)
    }

    private func stat(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State of health over time")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

            Chart(samples) { sample in
                LineMark(
                    x: .value("Date", sample.recordedAt),
                    y: .value("State of health", sample.sohPct)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Theme.regenGreen)

                PointMark(
                    x: .value("Date", sample.recordedAt),
                    y: .value("State of health", sample.sohPct)
                )
                .symbolSize(24)
                .foregroundStyle(Theme.regenGreen)
            }
            .chartYScale(domain: chartDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let pct = value.as(Double.self) {
                            Text(String(format: "%.0f%%", pct))
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textSecondary)
            Text(samples.isEmpty ? "No history yet" : "One reading so far")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(
                "Connect the adapter with a profile that reports state of health — VoltLink stores one reading per day and charts the trend once there are two."
            )
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard()
        .padding(.horizontal)
    }
}

#Preview("Battery Health") {
    NavigationStack {
        BatteryHealthView(vehicleData: VehicleDataManager())
    }
    .modelContainer(for: BatteryHealthSampleModel.self, inMemory: true)
}
