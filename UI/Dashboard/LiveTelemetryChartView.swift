import SwiftUI
import Charts

public struct LiveTelemetryChartView: View {
    public var telemetryHistory: [TelemetrySnapshot]
    /// Up to 2 metrics plotted on one shared y-axis. Defaults to today's power-only stream.
    public var seriesMetrics: [TelemetryMetric]
    public var liveMetrics: Set<TelemetryMetric>
    public var isDemoMode: Bool

    public init(telemetryHistory: [TelemetrySnapshot], seriesMetrics: [TelemetryMetric] = [.power], liveMetrics: Set<TelemetryMetric> = [], isDemoMode: Bool = false) {
        self.telemetryHistory = telemetryHistory
        self.seriesMetrics = seriesMetrics
        self.liveMetrics = liveMetrics
        self.isDemoMode = isDemoMode
    }

    private var headerTitle: String {
        seriesMetrics.map(\.displayName).joined(separator: " & ")
    }

    private func color(for metric: TelemetryMetric, value: Double, seriesIndex: Int) -> Color {
        if metric == .regenPower { return Theme.regenGreen }
        if metric == .power {
            return value < 0 ? Theme.regenGreen : Theme.textPrimary
        }
        return seriesIndex == 0 ? Theme.textPrimary : Theme.highPowerAmber
    }

    public var body: some View {
        let activeMetrics = seriesMetrics.filter { metric in
            telemetryHistory.last.map { metric.isAvailable(in: $0, liveMetrics: liveMetrics, isDemoMode: isDemoMode, at: .now) } ?? false
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(headerTitle, systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(activeMetrics.isEmpty ? "Waiting" : "Live")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Chart {
                ForEach(Array(activeMetrics.enumerated()), id: \.offset) { seriesIndex, metric in
                    ForEach(telemetryHistory.suffix(30).filter { metric.isAvailable(in: $0, liveMetrics: liveMetrics, isDemoMode: isDemoMode) }, id: \.timestamp) { item in
                        let value = metric.value(in: item)
                        let seriesColor = color(for: metric, value: value, seriesIndex: seriesIndex)

                        LineMark(
                            x: .value("Time", item.timestamp),
                            y: .value(metric.displayName, value)
                        )
                        .foregroundStyle(seriesColor)
                        .interpolationMethod(.catmullRom)

                        if activeMetrics.count == 1 {
                            AreaMark(
                                x: .value("Time", item.timestamp),
                                yStart: .value("Zero", 0.0),
                                yEnd: .value(metric.displayName, value)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [seriesColor.opacity(0.35), seriesColor.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                }
            }
            .frame(height: 140)
            .overlay {
                if activeMetrics.isEmpty {
                    ContentUnavailableView("No live telemetry", systemImage: "waveform.path.ecg")
                }
            }
        }
        .padding(16)
        .glassCard()
    }
}
