import Foundation

public enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }

    /// Approximate rendered height, matching the app's existing widget heights.
    public var height: Double {
        switch self {
        case .small: return 120
        case .medium: return 140
        case .large: return 240
        }
    }
}

public enum MetricDisplayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case numeric, dial, bar
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .numeric: return "Number"
        case .dial: return "Dial"
        case .bar: return "Bar"
        }
    }
}

public enum DashboardWidgetKind: Hashable, Sendable {
    case metric(TelemetryMetric)
    /// Up to 2 metrics plotted on a shared axis for readability.
    case chart(series: [TelemetryMetric])
}

extension DashboardWidgetKind: Codable {
    private enum CodingKeys: String, CodingKey { case type, metric, series }
    private enum Kind: String, Codable { case metric, chart }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .metric:
            self = .metric(try container.decode(TelemetryMetric.self, forKey: .metric))
        case .chart:
            self = .chart(series: try container.decode([TelemetryMetric].self, forKey: .series))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metric(let metric):
            try container.encode(Kind.metric, forKey: .type)
            try container.encode(metric, forKey: .metric)
        case .chart(let series):
            try container.encode(Kind.chart, forKey: .type)
            try container.encode(series, forKey: .series)
        }
    }
}

public struct DashboardWidgetConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: DashboardWidgetKind
    public var style: MetricDisplayStyle
    public var size: WidgetSize

    public init(id: UUID = UUID(), kind: DashboardWidgetKind, style: MetricDisplayStyle, size: WidgetSize) {
        self.id = id
        self.kind = kind
        self.style = style
        self.size = size
    }
}

/// Not itself `Codable` — deliberately encodes/decodes only `widgets` (see below),
/// since a type that's both synthesized-`Codable` and `RawRepresentable<String>` with a
/// `JSONEncoder(self)`-based `rawValue` recurses infinitely (Swift picks the
/// `RawRepresentable`-provided `encode(to:)` over the synthesized one).
public struct DashboardLayout: Equatable, Sendable {
    public var widgets: [DashboardWidgetConfig]

    public init(widgets: [DashboardWidgetConfig]) {
        self.widgets = widgets
    }
}

extension DashboardLayout: RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let widgets = try? JSONDecoder().decode([DashboardWidgetConfig].self, from: data) else { return nil }
        self.widgets = widgets
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(widgets),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}

extension DashboardLayout {
    /// Reproduces today's fixed widget set/order/sizes, so first run is visually unchanged.
    public static let `default` = DashboardLayout(widgets: [
        DashboardWidgetConfig(kind: .metric(.speed), style: .numeric, size: .small),
        DashboardWidgetConfig(kind: .metric(.aux12V), style: .numeric, size: .small),
        DashboardWidgetConfig(kind: .metric(.power), style: .dial, size: .large),
        DashboardWidgetConfig(kind: .metric(.soc), style: .bar, size: .medium),
        DashboardWidgetConfig(kind: .metric(.batteryTemp), style: .numeric, size: .small),
        DashboardWidgetConfig(kind: .chart(series: [.power]), style: .numeric, size: .large)
    ])
}

/// Packs widgets into rows: adjacent `.small` widgets pair up two-per-row;
/// `.medium`/`.large` each take a full-width row of their own.
public func packDashboardWidgetsIntoRows(_ widgets: [DashboardWidgetConfig]) -> [[DashboardWidgetConfig]] {
    var rows: [[DashboardWidgetConfig]] = []
    var pendingSmall: DashboardWidgetConfig?

    for widget in widgets {
        if widget.size == .small {
            if let pending = pendingSmall {
                rows.append([pending, widget])
                pendingSmall = nil
            } else {
                pendingSmall = widget
            }
        } else {
            if let pending = pendingSmall {
                rows.append([pending])
                pendingSmall = nil
            }
            rows.append([widget])
        }
    }

    if let pending = pendingSmall {
        rows.append([pending])
    }

    return rows
}
