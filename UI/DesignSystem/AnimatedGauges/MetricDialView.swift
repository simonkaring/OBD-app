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
    public var isUnavailable: Bool = false

    public init(value: Double, range: ClosedRange<Double>, mode: DialMode = .unidirectional, unit: String, label: String, isUnavailable: Bool = false) {
        self.value = value
        self.range = range
        self.mode = mode
        self.unit = unit
        self.label = label
        self.isUnavailable = isUnavailable
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

    private var statusText: String {
        guard case .bidirectional = mode else { return label.uppercased() }
        if value < -0.5 { return "REGEN" }
        if value > 5.0 { return "DRAW" }
        return "IDLE"
    }

    public var body: some View {
        GeometryReader { geo in
            let minDimension = min(geo.size.width, geo.size.height)
            let strokeWidth: CGFloat = max(6, minDimension * 0.09)
            let inset = strokeWidth / 2.0 + 2.0
            let dialDiameter = max(10, minDimension - (inset * 2.0))
            let valueFontSize: CGFloat = max(18, minDimension * 0.22)
            let unitFontSize: CGFloat = max(10, minDimension * 0.09)
            let labelFontSize: CGFloat = max(8, minDimension * 0.07)

            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: dialDiameter, height: dialDiameter)

                switch mode {
                case .bidirectional:
                    if isNegativeArc {
                        Circle()
                            .trim(from: 0.5 + (normalizedProgress * 0.35), to: 0.5)
                            .stroke(Theme.regenGradient, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                            .rotationEffect(.degrees(90))
                            .frame(width: dialDiameter, height: dialDiameter)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
                    } else {
                        Circle()
                            .trim(from: 0.5, to: 0.5 + (normalizedProgress * 0.35))
                            .stroke(Theme.powerGradient, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                            .rotationEffect(.degrees(90))
                            .frame(width: dialDiameter, height: dialDiameter)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
                    }
                case .unidirectional:
                    Circle()
                        .trim(from: 0.15, to: 0.15 + (normalizedProgress * 0.70))
                        .stroke(Theme.powerGradient, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(90))
                        .frame(width: dialDiameter, height: dialDiameter)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
                }

                VStack(spacing: minDimension * 0.02) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(isUnavailable ? "--" : String(format: value >= 100 ? "%.0f" : "%.1f", abs(value)))
                            .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(isNegativeArc ? Theme.regenGreen : Theme.textPrimary)
                        Text(unit)
                            .font(.system(size: unitFontSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Text(statusText)
                        .font(.system(size: labelFontSize, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, max(4, minDimension * 0.04))
                        .padding(.vertical, max(2, minDimension * 0.015))
                        .background(isNegativeArc ? Theme.regenGreen.opacity(0.2) : Theme.electricCyan.opacity(0.2))
                        .foregroundColor(isNegativeArc ? Theme.regenGreen : Theme.electricCyan)
                        .cornerRadius(6)
                }
                .padding(.horizontal, strokeWidth + 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .opacity(isUnavailable ? 0.4 : 1.0)
    }
}
