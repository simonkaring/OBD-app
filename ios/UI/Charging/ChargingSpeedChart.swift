import Charts
import SwiftUI

/// One charge-power reading placed on a session timeline.
public struct ChargingSpeedPoint: Sendable, Equatable {
    /// Minutes elapsed since the first reading of the session.
    public let minute: Double
    /// Charge power in kW (SI); the chart converts it through `UnitPreferences`.
    public let powerKW: Double

    public init(minute: Double, powerKW: Double) {
        self.minute = minute
        self.powerKW = powerKW
    }
}

/// Builds charging-speed curves from persisted session samples or live tracker history.
public enum ChargingSpeedCurve {
    /// Curve of a recorded session, ordered by time. Sessions recorded before schema V2 have no samples.
    public static func session(_ samples: [ChargingSampleModel], limit: Int = 90) -> [ChargingSpeedPoint] {
        let readings =
            samples
            .filter { $0.powerKW.isFinite && $0.timestamp.timeIntervalSince1970.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
            .map { (timestamp: $0.timestamp, powerKW: $0.powerKW) }
        return curve(readings, limit: limit)
    }

    /// Curve of the in-progress session, which `ChargingSessionTracker` samples every ~2 s.
    public static func live(_ history: [ChargingDataPoint], limit: Int = 180) -> [ChargingSpeedPoint] {
        curve(history.map { (timestamp: $0.timestamp, powerKW: $0.powerKW) }, limit: limit)
    }

    private static func curve(_ readings: [(timestamp: Date, powerKW: Double)], limit: Int) -> [ChargingSpeedPoint] {
        guard readings.count > 1, let origin = readings.first?.timestamp else { return [] }
        let points = readings.map {
            ChargingSpeedPoint(
                minute: max(0, $0.timestamp.timeIntervalSince(origin)) / 60,
                powerKW: max(0, $0.powerKW))
        }
        return points.downsampled(limit: limit)
    }
}

extension Array where Element == ChargingSpeedPoint {
    /// Evenly spaced subset so a long session stays cheap to render in a list row.
    public func downsampled(limit: Int) -> [ChargingSpeedPoint] {
        guard limit > 1, count > limit else { return self }
        let step = Double(count - 1) / Double(limit - 1)
        return (0..<limit).map { self[Int((Double($0) * step).rounded())] }
    }
}

/// Charge power over time: a full chart on the Charging tab, a compact sparkline in the Charging log.
public struct ChargingSpeedChart: View {
    public var points: [ChargingSpeedPoint]
    public var isCompact: Bool

    public init(points: [ChargingSpeedPoint], isCompact: Bool = false) {
        self.points = points
        self.isCompact = isCompact
    }

    public var body: some View {
        if isCompact {
            chart
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 38)
                .accessibilityLabel("Charging speed over time")
        } else {
            chart
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
                .chartYAxisLabel(UnitPreferences.shared.powerUnit.symbol, position: .leading)
                .frame(height: 180)
                .accessibilityLabel("Charging speed over time")
        }
    }

    private var chart: some View {
        let units = UnitPreferences.shared
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

                if !isCompact {
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
            }
        }
        .chartYScale(domain: 0...(peak * 1.1))
    }
}
