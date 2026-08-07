#if os(iOS)
import Foundation
import ActivityKit

public struct VoltLinkActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var speedKmH: Double
        public var powerKW: Double
        public var socPct: Double
        public var isCharging: Bool
        public var chargePowerKW: Double

        public init(speedKmH: Double, powerKW: Double, socPct: Double, isCharging: Bool = false, chargePowerKW: Double = 0.0) {
            self.speedKmH = speedKmH
            self.powerKW = powerKW
            self.socPct = socPct
            self.isCharging = isCharging
            self.chargePowerKW = chargePowerKW
        }
    }

    public var vehicleName: String

    public init(vehicleName: String = "Mercedes EQA 250") {
        self.vehicleName = vehicleName
    }
}
#endif

