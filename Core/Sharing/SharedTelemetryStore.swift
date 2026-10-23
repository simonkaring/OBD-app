import Foundation

/// Display units mirrored into the widget extension.
///
/// `UnitPreferences` lives in `Core/Units`, which only the app target compiles, so the
/// app writes its selected units alongside the SI snapshot and the widget converts at
/// render time. Telemetry itself stays SI in both processes.
public struct SharedDisplayUnits: Codable, Hashable, Sendable {
    public enum Distance: String, Codable, Sendable {
        case kilometers
        case miles

        public var symbol: String { self == .kilometers ? "km" : "mi" }
        public var perHourSymbol: String { self == .kilometers ? "km/h" : "mph" }
    }

    public enum Power: String, Codable, Sendable {
        case kilowatts
        case horsepower

        public var symbol: String { self == .kilowatts ? "kW" : "hp" }
    }

    public var distance: Distance
    public var power: Power

    public init(distance: Distance = .kilometers, power: Power = .kilowatts) {
        self.distance = distance
        self.power = power
    }

    /// Same constants as `UnitPreferences`; duplicated because the extension only
    /// compiles `Core/Sharing`.
    private static let kilometersPerMile = 1.609_344
    private static let kilowattsPerHorsepower = 0.745_699_872

    public var distanceSymbol: String { distance.symbol }
    public var speedSymbol: String { distance.perHourSymbol }
    public var powerSymbol: String { power.symbol }

    public func distance(kilometers: Double) -> Double {
        distance == .kilometers ? kilometers : kilometers / Self.kilometersPerMile
    }

    public func speed(kilometersPerHour: Double) -> Double {
        distance == .kilometers ? kilometersPerHour : kilometersPerHour / Self.kilometersPerMile
    }

    public func power(kilowatts: Double) -> Double {
        power == .kilowatts ? kilowatts : kilowatts / Self.kilowattsPerHorsepower
    }
}

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
    public var units: SharedDisplayUnits

    /// How long a snapshot still describes the car. Nothing refreshes the app group once
    /// the app is suspended, so a widget must not keep claiming last night's values.
    public static let maximumAge: TimeInterval = 120

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
        updatedAt: Date = Date(),
        units: SharedDisplayUnits = SharedDisplayUnits()
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
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case vehicleName, socPct, powerKW, speedKmH, rangeKm, isCharging, isConnected, isDemoMode, isTripActive, distanceKm, updatedAt, units
    }

    /// Tolerates snapshots written before later fields (`speedKmH`, `units`, …) existed.
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
        units = try container.decodeIfPresent(SharedDisplayUnits.self, forKey: .units) ?? SharedDisplayUnits()
    }

    /// `true` once the snapshot no longer describes the car (app suspended or killed).
    /// Snapshots from older builds decode `updatedAt` as `.distantPast`, so they count
    /// as expired rather than as live data.
    public func isStale(at date: Date = .now, maximumAge: TimeInterval = SharedTelemetrySnapshot.maximumAge) -> Bool {
        date.timeIntervalSince(updatedAt) > maximumAge
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

    /// The snapshot only if it is still fresh enough to describe the car.
    public static func loadFresh(
        maxAge: TimeInterval = SharedTelemetrySnapshot.maximumAge,
        now: Date = .now,
        defaults: UserDefaults? = nil
    ) -> SharedTelemetrySnapshot? {
        guard let snapshot = load(defaults: defaults), !snapshot.isStale(at: now, maximumAge: maxAge) else { return nil }
        return snapshot
    }
}

#if canImport(WidgetKit)
import WidgetKit

/// Coalesces widget refreshes: telemetry publishes up to several times per second,
/// while WidgetKit budgets a few dozen timeline reloads per day.
@MainActor
public enum SharedWidgetRefresher {
    private static var lastReload = Date.distantPast
    private static var lastSignature: String?
    private static let minimumInterval: TimeInterval = 60

    public static func refreshIfNeeded(for snapshot: SharedTelemetrySnapshot, at date: Date = .now, force: Bool = false) {
        let signature = signature(of: snapshot)
        guard force || (signature != lastSignature && date.timeIntervalSince(lastReload) >= minimumInterval) else { return }
        lastReload = date
        lastSignature = signature
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Only the values the widget draws, rounded to the precision it draws them at, so
    /// sub-percent SoC drift does not spend a reload.
    private static func signature(of snapshot: SharedTelemetrySnapshot) -> String {
        let units = snapshot.units
        return [
            snapshot.vehicleName,
            String(Int(snapshot.socPct.rounded())),
            String(Int(units.power(kilowatts: snapshot.powerKW).rounded())),
            String(Int(units.speed(kilometersPerHour: snapshot.speedKmH).rounded())),
            String(Int(units.distance(kilometers: snapshot.rangeKm ?? 0).rounded())),
            String(Int(units.distance(kilometers: snapshot.distanceKm).rounded())),
            snapshot.isCharging ? "charging" : "idle",
            snapshot.isConnected ? "connected" : "disconnected",
            snapshot.isTripActive ? "trip" : "parked",
            units.distanceSymbol,
            units.powerSymbol,
        ].joined(separator: "|")
    }
}
#endif
