import Foundation
import SwiftData

@Model
public final class ChargingSessionModel {
    public var id: UUID = UUID()
    public var startTime: Date = Date()
    public var endTime: Date?
    public var startSocPct: Double = 0
    public var endSocPct: Double = 0
    public var totalKWhDelivered: Double = 0
    public var peakPowerKW: Double = 0
    public var averagePowerKW: Double = 0
    public var locationName: String = "Fast Charger"
    public var latitude: Double?
    public var longitude: Double?

    /// Power/SOC points captured while charging, used to draw the session curve.
    /// Empty for sessions recorded before schema V2. Optional for CloudKit sync; read it
    /// through `curveSamples`.
    @Relationship(deleteRule: .cascade, inverse: \ChargingSampleModel.session)
    public var samples: [ChargingSampleModel]? = []

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

    /// Non-optional curve for read-only callers.
    public var curveSamples: [ChargingSampleModel] {
        samples ?? []
    }
}

/// One point on a charging session's power-vs-SOC curve.
@Model
public final class ChargingSampleModel {
    public var timestamp: Date = Date()
    public var socPct: Double = 0
    public var powerKW: Double = 0
    public var session: ChargingSessionModel?

    public init(timestamp: Date = Date(), socPct: Double = 0, powerKW: Double = 0) {
        self.timestamp = timestamp
        self.socPct = socPct
        self.powerKW = powerKW
    }
}

@Model
public final class SavedDTCModel {
    public var id: UUID = UUID()
    public var scanDate: Date = Date()
    public var code: String = ""
    public var title: String = ""
    public var category: String = ""
    public var severityRaw: String = ""
    public var freezeFrameSummary: String = ""

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
