import Foundation
import SwiftData

/// One persisted state-of-health reading for the high-voltage battery.
///
/// Most EV profiles already decode SOH live, but until now the value was only shown on the
/// dashboard and thrown away with the next poll. Keeping one row per day makes degradation
/// visible over months, which is the question owners and used-car buyers actually have.
@Model
public final class BatteryHealthSampleModel {
    public var id: UUID = UUID()
    public var recordedAt: Date = Date()
    public var sohPct: Double = 0
    public var socPct: Double = 0
    public var batteryTempC: Double = 0
    /// Distance this app has recorded from trips when the reading was taken. This is not the
    /// vehicle odometer — it only counts drives that VoltLink recorded.
    public var recordedDistanceKm: Double = 0
    public var vehicleName: String = ""

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        sohPct: Double,
        socPct: Double = 0,
        batteryTempC: Double = 0,
        recordedDistanceKm: Double = 0,
        vehicleName: String = ""
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.sohPct = sohPct
        self.socPct = socPct
        self.batteryTempC = batteryTempC
        self.recordedDistanceKm = recordedDistanceKm
        self.vehicleName = vehicleName
    }
}
