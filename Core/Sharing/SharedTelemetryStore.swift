import Foundation

/// The small telemetry snapshot shared with the widget extension through the app group.
///
/// The widget never opens the SwiftData store or touches CoreBluetooth: the app writes
/// this value after each applied telemetry update and the widget renders it read-only.
public struct SharedTelemetrySnapshot: Codable, Sendable, Equatable {
    public var vehicleName: String
    public var socPct: Double
    public var powerKW: Double
    public var speedKmH: Double
    public var rangeKm: Double?
    public var isCharging: Bool
    public var isConnected: Bool
    public var isDemoMode: Bool
    public var isTripActive: Bool
    public var distanceKm: Double
    public var updatedAt: Date

    public init(
        vehicleName: String,
        socPct: Double,
        powerKW: Double = 0,
        speedKmH: Double = 0,
        rangeKm: Double? = nil,
        isCharging: Bool = false,
        isConnected: Bool = false,
        isDemoMode: Bool = false,
        isTripActive: Bool = false,
        distanceKm: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.vehicleName = vehicleName
        self.socPct = socPct
        self.powerKW = powerKW
        self.speedKmH = speedKmH
        self.rangeKm = rangeKm
        self.isCharging = isCharging
        self.isConnected = isConnected
        self.isDemoMode = isDemoMode
        self.isTripActive = isTripActive
        self.distanceKm = distanceKm
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case vehicleName, socPct, powerKW, speedKmH, rangeKm, isCharging, isConnected, isDemoMode, isTripActive, distanceKm, updatedAt
    }

    /// Tolerates snapshots written before `speedKmH` existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vehicleName = try container.decode(String.self, forKey: .vehicleName)
        socPct = try container.decode(Double.self, forKey: .socPct)
        powerKW = try container.decodeIfPresent(Double.self, forKey: .powerKW) ?? 0
        speedKmH = try container.decodeIfPresent(Double.self, forKey: .speedKmH) ?? 0
        rangeKm = try container.decodeIfPresent(Double.self, forKey: .rangeKm)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
        isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? false
        isDemoMode = try container.decodeIfPresent(Bool.self, forKey: .isDemoMode) ?? false
        isTripActive = try container.decodeIfPresent(Bool.self, forKey: .isTripActive) ?? false
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

public enum SharedTelemetryStore {
    /// Must match `com.apple.security.application-groups` in both entitlements files.
    public static let appGroupID = "group.com.simonkaring.voltlink"
    static let snapshotKey = "shared.telemetry.snapshot"

    /// The app group container is unavailable in unsigned/CLI contexts; fall back to the
    /// standard defaults so the app keeps working (the widget simply shows placeholder
    /// data until a signed build provides the shared container).
    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func save(_ snapshot: SharedTelemetrySnapshot, defaults: UserDefaults? = nil) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        (defaults ?? Self.defaults()).set(data, forKey: snapshotKey)
    }

    public static func load(defaults: UserDefaults? = nil) -> SharedTelemetrySnapshot? {
        guard let data = (defaults ?? Self.defaults()).data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(SharedTelemetrySnapshot.self, from: data)
    }
}

#if canImport(WidgetKit)
import WidgetKit

/// Coalesces widget refreshes: telemetry publishes up to several times per second,
/// while WidgetKit only needs a new timeline a few times per minute.
@MainActor
public enum SharedWidgetRefresher {
    private static var lastReload = Date.distantPast
    private static let minimumInterval: TimeInterval = 10

    public static func refreshIfNeeded(at date: Date = .now, force: Bool = false) {
        guard force || date.timeIntervalSince(lastReload) >= minimumInterval else { return }
        lastReload = date
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
