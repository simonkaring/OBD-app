import SwiftUI

public enum DialMode: Sendable {
    /// Fills 0...range.upperBound in one direction (speed, SOC, fuel level, ...).
    case unidirectional
    /// Fills toward positive or negative independently (power draw vs. regen).
    case bidirectional(negativeMax: Double)
}

/// Generic arc/dial gauge — a metric-agnostic generalization of the app's original
/// circular power gauge arc-trim math, usable for any `TelemetryMetric`.
public struct MetricDialView: View {
    public var value: Double
    public var range: ClosedRange<Double>
    public var mode: DialMode
    public var unit: String
    public var label: String
    public var metric: TelemetryMetric?
    public var isUnavailable: Bool = false
    /// Full-charge range used to derive the SoC dial's "estimated range" toggle. Should come
    /// from the active `VehicleProfile.estimatedFullRangeKm`; defaults to a generic EV figure
    /// when no profile is available (e.g. rendered standalone).
    public var estimatedFullRangeKm: Double = 400.0

    @State private var showEstimatedRange: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Double, range: ClosedRange<Double>, mode: DialMode = .unidirectional, unit: String, label: String, metric: TelemetryMetric? = nil, isUnavailable: Bool = false, estimatedFullRangeKm: Double = 400.0) {
        self.value = value
        self.range = range
        self.mode = mode
        self.unit = unit
        self.label = label
        self.metric = metric
        self.isUnavailable = isUnavailable
        self.estimatedFullRangeKm = estimatedFullRangeKm
    }

    private var isNegativeArc: Bool {
        if case .bidirectional = mode, value < 0 { return true }
        return false
    }

    private var normalizedProgress: Double {
        switch mode {
        case .unidirectional:
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return min(1.0, max(0.0, (value - range.lowerBound) / span))
        case .bidirectional(let negativeMax):
            if value >= 0 {
                return min(1.0, value / max(range.upperBound, 0.0001))
            } else {
                return max(-1.0, value / max(negativeMax, 0.0001))
            }
        }
    }

    private var activeGradient: LinearGradient {
        if let metric = metric {
            switch metric {
            case .speed:
                return Theme.speedGradient
            case .soc:
                return value < 20 ? Theme.socLowGradient : Theme.socGradient
            case .power:
                return isNegativeArc ? Theme.regenGradient : Theme.powerGradient
            default:
                break
            }
        }
        return isNegativeArc ? Theme.regenGradient : Theme.powerGradient
    }

    private var statusText: String {
        if isUnavailable { return label }
        if metric == .soc {
            return showEstimatedRange ? "Est. range" : "State of charge"
        }
        guard case .bidirectional = mode else { return label }
        if value < -0.5 { return "Regen" }
        if value > 5.0 { return "Draw" }
        return "Idle"
    }

    private var displayValueAndUnit: (displayVal: String, displayUnit: String) {
        if metric == .soc && showEstimatedRange {
            let estimatedKm = (value / 100.0) * estimatedFullRangeKm
            return (String(format: "%.0f", estimatedKm), "km")
        }
        let decimals = metric?.decimalPlaces ?? (value >= 100 ? 0 : 1)
        let formatted = String(format: "%.\(decimals)f", abs(value))
        return (formatted, unit)
    }

    public var body: some View {
        GeometryReader { geo in
            let minDimension = min(geo.size.width, geo.size.height)
            let strokeWidth: CGFloat = max(6, minDimension * 0.09)
            let inset = strokeWidth / 2.0 + 2.0
            let dialDiameter = max(10, minDimension - (inset * 2.0))
            let valueFontSize: CGFloat = max(18, minDimension * 0.22)
            let unitFontSize: CGFloat = max(10, minDimension * 0.09)
            let labelFontSize: CGFloat = max(12, minDimension * 0.065)

            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(Theme.trackBackground, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: dialDiameter, height: dialDiameter)

                if !isUnavailable {
                    switch mode {
                    case .bidirectional:
                        if isNegativeArc {
                            Circle()
                                .trim(from: 0.5 + (normalizedProgress * 0.35), to: 0.5)
                                .stroke(activeGradient, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                                .rotationEffect(.degrees(90))
                                .frame(width: dialDiameter, height: dialDiameter)
                        } else {
                            Circle()
                                .trim(from: 0.5, to: 0.5 + (normalizedProgress * 0.35))
                                .stroke(activeGradient, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                                .rotationEffect(.degrees(90))
                                .frame(width: dialDiameter, height: dialDiameter)
                        }
                    case .unidirectional:
                        Circle()
                            .trim(from: 0.15, to: 0.15 + (normalizedProgress * 0.70))
                            .stroke(activeGradient, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                            .rotationEffect(.degrees(90))
                            .frame(width: dialDiameter, height: dialDiameter)
                    }
                }

                VStack(spacing: minDimension * 0.02) {
                    let valAndUnit = displayValueAndUnit
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(isUnavailable ? "--" : valAndUnit.displayVal)
                            .font(.system(size: valueFontSize, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(isNegativeArc ? Theme.regenGreen : Theme.textPrimary)
                        Text(valAndUnit.displayUnit)
                            .font(.system(size: unitFontSize))
                            .lineLimit(1)
                            .foregroundColor(Theme.textSecondary)
                    }

                    HStack(spacing: 3) {
                        Text(statusText)
                            .font(.system(size: labelFontSize, weight: .semibold))
                            .lineLimit(1)

                        if metric == .soc {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: labelFontSize * 0.9))
                        }
                    }
                    .padding(.horizontal, max(4, minDimension * 0.04))
                    .padding(.vertical, max(2, minDimension * 0.015))
                    .foregroundColor(metric == .soc || isNegativeArc ? Theme.regenGreen : Theme.gaugeCyan)
                    .background((metric == .soc || isNegativeArc ? Theme.regenGreen : Theme.gaugeCyan).opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, strokeWidth + 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: value)
            .contentShape(Rectangle())
            .onTapGesture {
                if metric == .soc {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showEstimatedRange.toggle()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isUnavailable ? "Unavailable" : "\(displayValueAndUnit.displayVal) \(displayValueAndUnit.displayUnit)")
        .accessibilityActions {
            if metric == .soc {
                Button(showEstimatedRange ? "Show percentage" : "Show estimated range") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showEstimatedRange.toggle()
                    }
                }
            }
        }
    }
}
