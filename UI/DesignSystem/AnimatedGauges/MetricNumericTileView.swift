import SwiftUI

/// Generic numeric readout tile — a metric-agnostic generalization of the app's
/// original speedometer look, usable for any `TelemetryMetric`.
public struct MetricNumericTileView: View {
    public var value: Double
    public var unit: String
    public var label: String
    public var decimalPlaces: Int = 0
    public var accentColor: Color = Theme.textSecondary
    public var isUnavailable: Bool = false

    public init(value: Double, unit: String, label: String, decimalPlaces: Int = 0, accentColor: Color = Theme.textSecondary, isUnavailable: Bool = false) {
        self.value = value
        self.unit = unit
        self.label = label
        self.decimalPlaces = decimalPlaces
        self.accentColor = accentColor
        self.isUnavailable = isUnavailable
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)

            Text(isUnavailable ? "--" : String(format: "%.\(decimalPlaces)f", value))
                .font(.system(size: 36, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundColor(Theme.textPrimary)
                .contentTransition(.numericText())

            Text(unit)
                .font(.subheadline)
                .foregroundColor(accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isUnavailable ? "Unavailable" : "\(String(format: "%.\(decimalPlaces)f", value)) \(unit)")
    }
}
