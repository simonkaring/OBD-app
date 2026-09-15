import Foundation

public enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case medium, large
    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "small", "medium": self = .medium
        case "large": self = .large
        default: self = .medium
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

    /// Only chart widgets need the rolling telemetry history array; metric tiles read the
    /// latest snapshot directly and shouldn't be handed (and re-diffed against) 50 stale points.
    public var isChart: Bool {
        if case .chart = self { return true }
        return false
    }
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

    /// Width is customizable independently of the space each visualization needs.
    public var preferredHeight: Double {
        if kind.isChart { return 200 }
        switch style {
        case .numeric: return 132
        case .bar: return 104
        case .dial: return size == .medium ? 180 : 220
        }
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

    // Explicit, since conforming to both Equatable and RawRepresentable would otherwise
    // resolve to the stdlib's RawRepresentable `==`, which compares `rawValue` JSON strings —
    // and JSONEncoder's key ordering isn't guaranteed stable across separate encode() calls.
    public static func == (lhs: DashboardLayout, rhs: DashboardLayout) -> Bool {
        lhs.widgets == rhs.widgets
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
    /// Speed and power dials, a compact full-width charge bar, then supporting metrics.
    public static let `default` = DashboardLayout(widgets: [
        DashboardWidgetConfig(kind: .metric(.speed), style: .dial, size: .medium),
        DashboardWidgetConfig(kind: .metric(.power), style: .dial, size: .medium),
        DashboardWidgetConfig(kind: .metric(.soc), style: .bar, size: .large),
        DashboardWidgetConfig(kind: .metric(.packVoltage), style: .numeric, size: .medium),
        DashboardWidgetConfig(kind: .metric(.batteryTemp), style: .numeric, size: .medium),
        DashboardWidgetConfig(kind: .chart(series: [.power]), style: .numeric, size: .large)
    ])
}

/// Packs widgets into 2-column grid rows:
/// - `.medium` widgets occupy 1 column (half-width, pairing 2 per row when adjacent)
/// - `.large` widgets occupy both columns (full-width single row)
public func packDashboardWidgetsIntoRows(_ widgets: [DashboardWidgetConfig]) -> [[DashboardWidgetConfig]] {
    var rows: [[DashboardWidgetConfig]] = []
    var pendingMedium: DashboardWidgetConfig?

    for widget in widgets {
        if widget.size == .medium {
            if let pending = pendingMedium {
                rows.append([pending, widget])
                pendingMedium = nil
            } else {
                pendingMedium = widget
            }
        } else { // .large
            if let pending = pendingMedium {
                rows.append([pending])
                pendingMedium = nil
            }
            rows.append([widget])
        }
    }

    if let pending = pendingMedium {
        rows.append([pending])
    }

    return rows
}
