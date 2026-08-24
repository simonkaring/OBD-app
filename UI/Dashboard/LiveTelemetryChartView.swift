import SwiftUI
import Charts

public struct LiveTelemetryChartView: View {
    public var telemetryHistory: [TelemetrySnapshot]
    /// Up to 2 metrics plotted on one shared y-axis. Defaults to today's power-only stream.
    public var seriesMetrics: [TelemetryMetric]

    public init(telemetryHistory: [TelemetrySnapshot], seriesMetrics: [TelemetryMetric] = [.power]) {
        self.telemetryHistory = telemetryHistory
        self.seriesMetrics = seriesMetrics
    }

    private var headerTitle: String {
        seriesMetrics.map(\.displayName).joined(separator: " & ")
    }

    private func color(for metric: TelemetryMetric, value: Double, seriesIndex: Int) -> Color {
        if metric == .power {
            return value < 0 ? Theme.regenGreen : Theme.electricCyan
        }
        return seriesIndex == 0 ? Theme.electricCyan : Theme.highPowerAmber
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live \(headerTitle) Stream", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("REALTIME")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.electricCyan.opacity(0.2))
                    .foregroundColor(Theme.electricCyan)
                    .cornerRadius(4)
            }

            Chart {
                ForEach(Array(seriesMetrics.enumerated()), id: \.offset) { seriesIndex, metric in
                    ForEach(telemetryHistory.suffix(30), id: \.timestamp) { item in
                        let value = metric.value(in: item)
                        let seriesColor = color(for: metric, value: value, seriesIndex: seriesIndex)

                        LineMark(
                            x: .value("Time", item.timestamp),
                            y: .value(metric.displayName, value)
                        )
                        .foregroundStyle(seriesColor)
                        .interpolationMethod(.catmullRom)

                        if seriesMetrics.count == 1 {
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
        }
        .padding(16)
        .glassCard()
    }
}
