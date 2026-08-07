import SwiftUI

/// Generic linear progress bar for a single metric — a metric-agnostic generalization
/// of the progress-bar half of `BatteryLevelBar`, usable for any `TelemetryMetric`.
public struct MetricBarView: View {
    public var value: Double
    public var range: ClosedRange<Double>
    public var unit: String
    public var label: String
    public var color: Color = Theme.electricCyan
    public var isUnavailable: Bool = false

    public init(value: Double, range: ClosedRange<Double>, unit: String, label: String, color: Color = Theme.electricCyan, isUnavailable: Bool = false) {
        self.value = value
        self.range = range
        self.unit = unit
        self.label = label
        self.color = color
        self.isUnavailable = isUnavailable
    }

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1.0, max(0.0, (value - range.lowerBound) / span))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(isUnavailable ? "--" : String(format: "%.0f %@", value, unit))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 20)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(0, geo.size.width * progress), height: 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
                    }
                }
                .frame(height: 20)
            }
        }
        .padding(16)
        .glassCard()
        .opacity(isUnavailable ? 0.4 : 1.0)
    }
}
