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
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(90))

            if isNegativeArc {
                Circle()
                    .trim(from: 0.5 + (normalizedProgress * 0.35), to: 0.5)
                    .stroke(Theme.regenGradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
            } else {
                Circle()
                    .trim(from: 0.5, to: 0.5 + (normalizedProgress * 0.35))
                    .stroke(Theme.powerGradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
            }

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(isUnavailable ? "--" : String(format: "%.1f", abs(value)))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(isNegativeArc ? Theme.regenGreen : Theme.textPrimary)
                    Text(unit)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }

                Text(statusText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isNegativeArc ? Theme.regenGreen.opacity(0.2) : Theme.electricCyan.opacity(0.2))
                    .foregroundColor(isNegativeArc ? Theme.regenGreen : Theme.electricCyan)
                    .cornerRadius(8)
            }
        }
        .padding(20)
        .opacity(isUnavailable ? 0.4 : 1.0)
    }
}
