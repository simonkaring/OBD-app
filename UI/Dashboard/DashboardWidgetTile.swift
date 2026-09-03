import SwiftUI

/// Renders one configured dashboard widget, dispatching on kind + style,
/// and marking metrics the active vehicle profile can't supply as unavailable.
public struct DashboardWidgetTile: View {
    public var config: DashboardWidgetConfig
    public var snapshot: TelemetrySnapshot
    public var profile: VehicleProfile
    public var supportedMetrics: Set<TelemetryMetric>
    public var liveMetrics: Set<TelemetryMetric>
    public var telemetryHistory: [TelemetrySnapshot]
    public var isConnected: Bool = true
    public var isDemoMode: Bool = false

    public init(config: DashboardWidgetConfig, snapshot: TelemetrySnapshot, profile: VehicleProfile, supportedMetrics: Set<TelemetryMetric>, liveMetrics: Set<TelemetryMetric>, telemetryHistory: [TelemetrySnapshot], isConnected: Bool = true, isDemoMode: Bool = false) {
        self.config = config
        self.snapshot = snapshot
        self.profile = profile
        self.supportedMetrics = supportedMetrics
        self.liveMetrics = liveMetrics
        self.telemetryHistory = telemetryHistory
        self.isConnected = isConnected
        self.isDemoMode = isDemoMode
    }

    public var body: some View {
        switch config.kind {
        case .metric(let metric):
            metricTile(metric)
        case .chart(let series):
            LiveTelemetryChartView(telemetryHistory: telemetryHistory, seriesMetrics: series, liveMetrics: liveMetrics, isDemoMode: isDemoMode)
        }
    }

    @ViewBuilder
    private func metricTile(_ metric: TelemetryMetric) -> some View {
        let isSupported = isDemoMode || supportedMetrics.contains(metric)
        let isAvailable = isDemoMode || (isSupported && isConnected && liveMetrics.contains(metric))
        let value = metric.value(in: snapshot)
        let range = metric.defaultRange
        let dialMode: DialMode = range.lowerBound < 0 ? .bidirectional(negativeMax: abs(range.lowerBound)) : .unidirectional

        Group {
            switch config.style {
            case .numeric:
                MetricNumericTileView(value: value, unit: metric.unitSymbol, label: metric.displayName, decimalPlaces: metric.decimalPlaces, isUnavailable: !isAvailable)
            case .dial:
                MetricDialView(value: value, range: range, mode: dialMode, unit: metric.unitSymbol, label: metric.displayName, metric: metric, isUnavailable: !isAvailable)
            case .bar:
                MetricBarView(value: value, range: range, unit: metric.unitSymbol, label: metric.displayName, isUnavailable: !isAvailable)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isSupported && !isDemoMode {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.highPowerAmber)
                    .padding(8)
                    .accessibilityLabel("Not supported by \(profile.vehicleName)")
            }
        }
    }
}
