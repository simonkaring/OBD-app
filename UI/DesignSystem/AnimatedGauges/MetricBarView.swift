import SwiftUI

/// Generic linear progress bar for a single metric — a metric-agnostic generalization
/// of the progress-bar half of `BatteryLevelBar`, usable for any `TelemetryMetric`.
public struct MetricBarView: View {
    public var value: Double
    public var range: ClosedRange<Double>
    public var unit: String
    public var label: String
    public var color: Color = Theme.textPrimary
    public var isUnavailable: Bool = false

    public init(value: Double, range: ClosedRange<Double>, unit: String, label: String, color: Color = Theme.textPrimary, isUnavailable: Bool = false) {
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
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(isUnavailable ? "--" : String(format: "%.0f %@", value, unit))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.textPrimary)
            }

            ProgressView(value: isUnavailable ? 0 : progress)
                .tint(color)

            HStack {
                Text(String(format: "Min: %.0f%@", range.lowerBound, unit))
                Spacer()
                Text(String(format: "Max: %.0f%@", range.upperBound, unit))
            }
            .font(.caption)
            .foregroundColor(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isUnavailable ? "Unavailable" : String(format: "%.0f %@", value, unit))
    }
}
