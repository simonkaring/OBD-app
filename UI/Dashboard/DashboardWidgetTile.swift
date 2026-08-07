import SwiftUI

/// Renders one configured dashboard widget, dispatching on kind + style,
/// and marking metrics the active vehicle profile can't supply as unavailable.
public struct DashboardWidgetTile: View {
    public var config: DashboardWidgetConfig
    public var snapshot: TelemetrySnapshot
    public var profile: VehicleProfile
    public var telemetryHistory: [TelemetrySnapshot]

    public init(config: DashboardWidgetConfig, snapshot: TelemetrySnapshot, profile: VehicleProfile, telemetryHistory: [TelemetrySnapshot]) {
        self.config = config
        self.snapshot = snapshot
        self.profile = profile
        self.telemetryHistory = telemetryHistory
    }

    public var body: some View {
        switch config.kind {
        case .metric(let metric):
            metricTile(metric)
        case .chart(let series):
            LiveTelemetryChartView(telemetryHistory: telemetryHistory, seriesMetrics: series)
        }
    }

    @ViewBuilder
    private func metricTile(_ metric: TelemetryMetric) -> some View {
        let isAvailable = profile.supportedMetrics.contains(metric)
        let value = metric.value(in: snapshot)
        let range = metric.defaultRange
        let dialMode: DialMode = range.lowerBound < 0 ? .bidirectional(negativeMax: abs(range.lowerBound)) : .unidirectional

        Group {
            switch config.style {
            case .numeric:
                MetricNumericTileView(value: value, unit: metric.unitSymbol, label: metric.displayName, isUnavailable: !isAvailable)
            case .dial:
                MetricDialView(value: value, range: range, mode: dialMode, unit: metric.unitSymbol, label: metric.displayName, isUnavailable: !isAvailable)
            case .bar:
                MetricBarView(value: value, range: range, unit: metric.unitSymbol, label: metric.displayName, isUnavailable: !isAvailable)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isAvailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.highPowerAmber)
                    .padding(8)
                    .accessibilityLabel("Not supported by \(profile.vehicleName)")
            }
        }
    }
}
