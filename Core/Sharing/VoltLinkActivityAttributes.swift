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

        public init(
            mode: Mode,
            socPct: Double,
            powerKW: Double,
            speedKmH: Double,
            distanceKm: Double,
            startedAt: Date
        ) {
            self.mode = mode
            self.socPct = socPct
            self.powerKW = powerKW
            self.speedKmH = speedKmH
            self.distanceKm = distanceKm
            self.startedAt = startedAt
        }
    }

    public var vehicleName: String

    public init(vehicleName: String) {
        self.vehicleName = vehicleName
    }
}
#endif
