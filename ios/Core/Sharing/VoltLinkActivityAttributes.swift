#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity shared between the app (which starts/updates it) and the widget
/// extension (which renders the Lock Screen / Dynamic Island presentation).
@available(iOS 16.2, *)
public struct VoltLinkActivityAttributes: ActivityAttributes {
    public enum Mode: String, Codable, Sendable {
        case trip
        case charging
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var mode: Mode
        public var socPct: Double
        public var powerKW: Double
        public var speedKmH: Double
        public var distanceKm: Double
        public var startedAt: Date
        /// The user's display units; the Lock Screen must not disagree with the app.
        public var units: SharedDisplayUnits
        /// Simulated values must not read as the car's real state.
        public var isDemoMode: Bool

        public init(
            mode: Mode,
            socPct: Double,
            powerKW: Double,
            speedKmH: Double,
            distanceKm: Double,
            startedAt: Date,
            units: SharedDisplayUnits = SharedDisplayUnits(),
            isDemoMode: Bool = false
        ) {
            self.mode = mode
            self.socPct = socPct
            self.powerKW = powerKW
            self.speedKmH = speedKmH
            self.distanceKm = distanceKm
            self.startedAt = startedAt
            self.units = units
            self.isDemoMode = isDemoMode
        }

        private enum CodingKeys: String, CodingKey {
            case mode, socPct, powerKW, speedKmH, distanceKm, startedAt, units, isDemoMode
        }

        /// Tolerates activities started before units were part of the state.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decode(Mode.self, forKey: .mode)
            socPct = try container.decode(Double.self, forKey: .socPct)
            powerKW = try container.decode(Double.self, forKey: .powerKW)
            speedKmH = try container.decode(Double.self, forKey: .speedKmH)
            distanceKm = try container.decode(Double.self, forKey: .distanceKm)
            startedAt = try container.decode(Date.self, forKey: .startedAt)
            units = try container.decodeIfPresent(SharedDisplayUnits.self, forKey: .units) ?? SharedDisplayUnits()
            isDemoMode = try container.decodeIfPresent(Bool.self, forKey: .isDemoMode) ?? false
        }
    }

    public var vehicleName: String

    public init(vehicleName: String) {
        self.vehicleName = vehicleName
    }
}
#endif
