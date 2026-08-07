import SwiftUI
import Charts

public struct LiveTelemetryChartView: View {
    public var telemetryHistory: [TelemetrySnapshot]

    public init(telemetryHistory: [TelemetrySnapshot]) {
        self.telemetryHistory = telemetryHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live Power & Speed Stream", systemImage: "chart.xyaxis.line")
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
                ForEach(telemetryHistory.suffix(30)) { item in
                    LineMark(
                        x: .value("Time", item.timestamp),
                        y: .value("Power (kW)", item.powerKW)
                    )
                    .foregroundStyle(item.powerKW < 0 ? Theme.regenGreen : Theme.electricCyan)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", item.timestamp),
                        y: .value("Power (kW)", item.powerKW)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [(item.powerKW < 0 ? Theme.regenGreen : Theme.electricCyan).opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
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
