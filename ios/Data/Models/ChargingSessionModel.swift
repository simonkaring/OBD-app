import Foundation
import SwiftData

@Model
public final class ChargingSessionModel {
    public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var startSocPct: Double
    public var endSocPct: Double
    public var totalKWhDelivered: Double
    public var peakPowerKW: Double
    public var averagePowerKW: Double
    public var locationName: String
    public var latitude: Double?
    public var longitude: Double?

    /// Power/SOC points captured while charging, used to draw the session curve.
    /// Empty for sessions recorded before schema V2.
    @Relationship(deleteRule: .cascade)
    public var samples: [ChargingSampleModel]

    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        startSocPct: Double = 0.0,
        locationName: String = "Fast Charger",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.startSocPct = startSocPct
        self.endSocPct = startSocPct
        self.totalKWhDelivered = 0.0
        self.peakPowerKW = 0.0
        self.averagePowerKW = 0.0
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.samples = []
    }
}

/// One point on a charging session's power-vs-SOC curve.
@Model
public final class ChargingSampleModel {
    public var timestamp: Date
    public var socPct: Double
    public var powerKW: Double

    public init(timestamp: Date = Date(), socPct: Double = 0, powerKW: Double = 0) {
        self.timestamp = timestamp
        self.socPct = socPct
        self.powerKW = powerKW
    }
}

@Model
public final class SavedDTCModel {
    public var id: UUID
    public var scanDate: Date
    public var code: String
    public var title: String
    public var category: String
    public var severityRaw: String
    public var freezeFrameSummary: String

    public init(
        id: UUID = UUID(),
        scanDate: Date = Date(),
        code: String,
        title: String,
        category: String,
        severityRaw: String,
        freezeFrameSummary: String = ""
    ) {
        self.id = id
        self.scanDate = scanDate
        self.code = code
        self.title = title
        self.category = category
        self.severityRaw = severityRaw
        self.freezeFrameSummary = freezeFrameSummary
    }
}
