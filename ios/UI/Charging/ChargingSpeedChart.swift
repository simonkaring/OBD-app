import Charts
import SwiftUI

/// One charge-power reading placed on a session timeline.
public struct ChargingSpeedPoint: Sendable, Equatable {
    /// Minutes elapsed since the first reading of the session.
    public let minute: Double
    /// Charge power in kW (SI); the chart converts it through `UnitPreferences`.
    public let powerKW: Double
    /// Battery level at the reading, when the source reported one.
    public let socPct: Double?

    public init(minute: Double, powerKW: Double, socPct: Double? = nil) {
        self.minute = minute
        self.powerKW = powerKW
        self.socPct = socPct
    }
}

/// Builds charging-speed curves from persisted session samples or live tracker history.
public enum ChargingSpeedCurve {
    /// Curve of a recorded session, ordered by time. Sessions recorded before schema V2 have no samples.
    public static func session(_ samples: [ChargingSampleModel], limit: Int = 240) -> [ChargingSpeedPoint] {
        let readings =
            samples
            .filter { $0.powerKW.isFinite && $0.timestamp.timeIntervalSince1970.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
            .map { (timestamp: $0.timestamp, powerKW: $0.powerKW, socPct: $0.socPct) }
        return curve(readings, limit: limit)
    }

    /// Curve of the in-progress session, which `ChargingSessionTracker` samples every ~2 s.
    public static func live(_ history: [ChargingDataPoint], limit: Int = 180) -> [ChargingSpeedPoint] {
        curve(history.map { (timestamp: $0.timestamp, powerKW: $0.powerKW, socPct: $0.soc) }, limit: limit)
    }

    private static func curve(
        _ readings: [(timestamp: Date, powerKW: Double, socPct: Double)],
        limit: Int
    ) -> [ChargingSpeedPoint] {
        guard readings.count > 1, let origin = readings.first?.timestamp else { return [] }
        let points = readings.map {
            ChargingSpeedPoint(
                minute: max(0, $0.timestamp.timeIntervalSince(origin)) / 60,
                powerKW: max(0, $0.powerKW),
                socPct: $0.socPct.isFinite && $0.socPct > 0 ? $0.socPct : nil)
        }
        return points.downsampled(limit: limit)
    }
}

extension Array where Element == ChargingSpeedPoint {
    /// Evenly spaced subset so a long session stays cheap to render.
    public func downsampled(limit: Int) -> [ChargingSpeedPoint] {
        guard limit > 1, count > limit else { return self }
        let step = Double(count - 1) / Double(limit - 1)
        return (0..<limit).map { self[Int((Double($0) * step).rounded())] }
    }
}

/// Charge power over time, with a scrubbable readout of elapsed time, speed, and state of charge.
public struct ChargingSpeedChart: View {
    public var points: [ChargingSpeedPoint]

    @State private var selectedMinute: Double?

    public init(points: [ChargingSpeedPoint]) {
        self.points = points
    }

    private var units: UnitPreferences { UnitPreferences.shared }

    /// Reading closest to the scrubbed minute, or `nil` while nothing is selected.
    private var selectedPoint: ChargingSpeedPoint? {
        guard let selectedMinute else { return nil }
        return points.min { abs($0.minute - selectedMinute) < abs($1.minute - selectedMinute) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            readout
        }
    }

    private var chart: some View {
        let peak = units.powerValue(fromKilowatts: max(points.map(\.powerKW).max() ?? 0, 1))
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                let value = units.powerValue(fromKilowatts: point.powerKW)

                LineMark(
                    x: .value("Minutes charging", point.minute),
                    y: .value("Charging speed", value)
                )
                .foregroundStyle(Theme.regenGreen)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Minutes charging", point.minute),
                    y: .value("Charging speed", value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.regenGreen.opacity(0.35), Theme.regenGreen.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom)
                )
                .interpolationMethod(.catmullRom)
            }

            if let selectedPoint {
                RuleMark(x: .value("Minutes charging", selectedPoint.minute))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(
                    x: .value("Minutes charging", selectedPoint.minute),
                    y: .value("Charging speed", units.powerValue(fromKilowatts: selectedPoint.powerKW))
                )
                .foregroundStyle(Theme.electricCyan)
                .symbolSize(70)
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(Theme.chartGrid)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.chartGrid)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .chartXAxisLabel("Minutes charging", position: .bottom)
        .chartYAxisLabel(units.powerUnit.symbol, position: .leading)
        .chartYScale(domain: 0...(peak * 1.1))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                select(minuteAt: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Charging speed over time")
        .accessibilityValue(
            selectedPoint.map { "\(ChargingSessionSummary.duration($0.minute * 60)), \(units.power(kilowatts: $0.powerKW))" } ?? "No point selected")
    }

    /// Maps a touch inside the plot area to the nearest chart minute, clamped to the session span.
    private func select(minuteAt location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let x = location.x - geometry[plotFrame].origin.x
        guard let minute: Double = proxy.value(atX: x), let lower = points.first?.minute, let upper = points.last?.minute else { return }
        selectedMinute = min(max(minute, lower), upper)
    }

    @ViewBuilder
    private var readout: some View {
        if let selectedPoint {
            HStack(spacing: 20) {
                readoutValue(ChargingSessionSummary.duration(selectedPoint.minute * 60), label: "Elapsed")
                readoutValue(units.power(kilowatts: selectedPoint.powerKW), label: "Speed")
                if let socPct = selectedPoint.socPct {
                    readoutValue(socPct.formatted(.number.precision(.fractionLength(0))) + "%", label: "Battery")
                }
                Spacer(minLength: 0)
            }
        } else {
            Label("Drag across the curve to inspect a moment", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func readoutValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
