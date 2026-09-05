import SwiftUI

/// Generic numeric readout tile — a metric-agnostic generalization of the app's
/// original speedometer look, usable for any `TelemetryMetric`.
public struct MetricNumericTileView: View {
    public var value: Double
    public var unit: String
    public var label: String
    public var decimalPlaces: Int = 0
    public var accentColor: Color = Theme.electricCyan
    public var isUnavailable: Bool = false

    public init(value: Double, unit: String, label: String, decimalPlaces: Int = 0, accentColor: Color = Theme.electricCyan, isUnavailable: Bool = false) {
        self.value = value
        self.unit = unit
        self.label = label
        self.decimalPlaces = decimalPlaces
        self.accentColor = accentColor
        self.isUnavailable = isUnavailable
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            Text(isUnavailable ? "--" : String(format: "%.\(decimalPlaces)f", value))
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .contentTransition(.numericText())

            Text(unit.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .tracking(2)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 28)
        .glassCard()
        .opacity(isUnavailable ? 0.4 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isUnavailable ? "Unavailable" : "\(String(format: "%.\(decimalPlaces)f", value)) \(unit)")
    }
}
