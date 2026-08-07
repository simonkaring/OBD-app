import Foundation

/// A CarPlay grid tile: either a telemetry metric, or the always-available Health tile
/// (driven by `DTCScannerService`, not a `TelemetrySnapshot` field).
public enum CarPlayTileKind: Hashable, Sendable {
    case metric(TelemetryMetric)
    case health
}

extension CarPlayTileKind: Codable {
    private enum CodingKeys: String, CodingKey { case type, metric }
    private enum Kind: String, Codable { case metric, health }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .metric:
            self = .metric(try container.decode(TelemetryMetric.self, forKey: .metric))
        case .health:
            self = .health
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .metric(let metric):
            try container.encode(Kind.metric, forKey: .type)
            try container.encode(metric, forKey: .metric)
        case .health:
            try container.encode(Kind.health, forKey: .type)
        }
    }
}

/// Persisted CarPlay tile selection/order. Capped at 8 — `CPGridTemplate`'s hard platform limit.
/// Not itself `Codable` — see `DashboardLayout`'s doc comment for why `rawValue` encodes
/// `tiles` directly rather than `self`.
public struct CarPlayLayout: Equatable, Sendable {
    public static let maxTiles = 8

    public var tiles: [CarPlayTileKind]

    public init(tiles: [CarPlayTileKind]) {
        self.tiles = Array(tiles.prefix(Self.maxTiles))
    }
}

extension CarPlayLayout: RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let tiles = try? JSONDecoder().decode([CarPlayTileKind].self, from: data) else { return nil }
        self.tiles = tiles
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(tiles),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}

extension CarPlayLayout {
    public static let storageKey = "carPlayLayout"
    public static let `default` = CarPlayLayout(tiles: [.metric(.soc), .metric(.power), .metric(.speed), .health])

    /// Reads the persisted layout outside SwiftUI (e.g. from `CarPlaySceneDelegate`, a plain `UIResponder`).
    public static func load() -> CarPlayLayout {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let layout = CarPlayLayout(rawValue: raw) else {
            return .default
        }
        return layout
    }
}
