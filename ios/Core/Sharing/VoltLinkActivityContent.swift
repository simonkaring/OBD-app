import Foundation

/// Payload of the VoltLink Live Activity.
///
/// Declared outside the ActivityKit guard so `swift test` can decode legacy payloads
/// and build states on macOS; `VoltLinkActivityAttributes` exposes it as its
/// `ContentState`.
public struct VoltLinkActivityContent: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case trip
        case charging
    }

    public var mode: Mode
    public var socPct: Double
    public var powerKW: Double
    public var speedKmH: Double
    public var distanceKm: Double
    /// Estimated remaining range at the current state of charge; nil without an estimate.
    public var rangeKm: Double?
    /// Trip average consumption; nil while the trip is too short or power data is incomplete.
    public var averageConsumptionKWhPer100Km: Double?
    /// Start of the trip or charging session, not of the activity, so a relaunch mid-trip
    /// keeps the elapsed clock honest.
    public var startedAt: Date
    public var units: SharedDisplayUnits
    public var isDemoMode: Bool

    public init(
        mode: Mode,
        socPct: Double,
        powerKW: Double,
        speedKmH: Double,
        distanceKm: Double,
        rangeKm: Double? = nil,
        averageConsumptionKWhPer100Km: Double? = nil,
        startedAt: Date,
        units: SharedDisplayUnits = SharedDisplayUnits(),
        isDemoMode: Bool = false
    ) {
        self.mode = mode
        self.socPct = socPct
        self.powerKW = powerKW
        self.speedKmH = speedKmH
        self.distanceKm = distanceKm
        self.rangeKm = rangeKm
        self.averageConsumptionKWhPer100Km = averageConsumptionKWhPer100Km
        self.startedAt = startedAt
        self.units = units
        self.isDemoMode = isDemoMode
    }

    private enum CodingKeys: String, CodingKey {
        case mode, socPct, powerKW, speedKmH, distanceKm, rangeKm, averageConsumptionKWhPer100Km, startedAt, units, isDemoMode
    }

    /// Tolerates activities started before range, consumption, and units were part of the state.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(Mode.self, forKey: .mode)
        socPct = try container.decode(Double.self, forKey: .socPct)
        powerKW = try container.decodeIfPresent(Double.self, forKey: .powerKW) ?? 0
        speedKmH = try container.decodeIfPresent(Double.self, forKey: .speedKmH) ?? 0
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm) ?? 0
        rangeKm = try container.decodeIfPresent(Double.self, forKey: .rangeKm)
        averageConsumptionKWhPer100Km = try container.decodeIfPresent(Double.self, forKey: .averageConsumptionKWhPer100Km)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        units = try container.decodeIfPresent(SharedDisplayUnits.self, forKey: .units) ?? SharedDisplayUnits()
        isDemoMode = try container.decodeIfPresent(Bool.self, forKey: .isDemoMode) ?? false
    }

    /// Builds the activity state from the app-group snapshot. `startedAt` comes from the
    /// recorder, so an activity restarted after an app relaunch still counts the whole trip.
    public static func make(mode: Mode, snapshot: SharedTelemetrySnapshot, startedAt: Date) -> Self {
        VoltLinkActivityContent(
            mode: mode,
            socPct: snapshot.socPct,
            powerKW: snapshot.powerKW,
            speedKmH: snapshot.speedKmH,
            distanceKm: snapshot.distanceKm,
            rangeKm: snapshot.rangeKm,
            averageConsumptionKWhPer100Km: mode == .trip ? snapshot.averageConsumptionKWhPer100Km : nil,
            startedAt: startedAt,
            units: snapshot.units,
            isDemoMode: snapshot.isDemoMode)
    }
}
