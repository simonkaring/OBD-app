import Foundation
import SwiftData

@Model
public final class TelemetryPointModel {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    public var speedKmH: Double
    public var powerKW: Double
    public var socPct: Double
    public var batteryTempC: Double

    public init(timestamp: Date = Date(), latitude: Double = 0.0, longitude: Double = 0.0, speedKmH: Double = 0.0, powerKW: Double = 0.0, socPct: Double = 0.0, batteryTempC: Double = 25.0) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmH = speedKmH
        self.powerKW = powerKW
        self.socPct = socPct
        self.batteryTempC = batteryTempC
    }

    public var hasValidCoordinate: Bool {
        (-90...90).contains(latitude) &&
            (-180...180).contains(longitude) &&
            !(latitude == 0 && longitude == 0)
    }
}

@Model
public final class TripModel {
    public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var distanceKm: Double
    public var startSocPct: Double
    public var endSocPct: Double
    public var totalKWhUsed: Double
    /// Nil for older recordings which did not track recovered energy.
    public var totalKWhRecovered: Double?
    public var averageSpeedKmH: Double
    public var maxPowerKW: Double
    public var maxRegenKW: Double
    public var vehicleName: String
    
    @Relationship(deleteRule: .cascade)
    public var samples: [TelemetryPointModel]

    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        distanceKm: Double = 0.0,
        startSocPct: Double = 0.0,
        vehicleName: String = "Vehicle"
    ) {
        self.id = id
        self.startTime = startTime
        self.distanceKm = distanceKm
        self.startSocPct = startSocPct
        self.endSocPct = startSocPct
        self.totalKWhUsed = 0.0
        self.totalKWhRecovered = 0.0
        self.averageSpeedKmH = 0.0
        self.maxPowerKW = 0.0
        self.maxRegenKW = 0.0
        self.vehicleName = vehicleName
        self.samples = []
    }

    public var efficiencyKWhPer100Km: Double {
        guard distanceKm > 0.1 else { return 0.0 }
        return ((totalKWhUsed - (totalKWhRecovered ?? 0)) / distanceKm) * 100.0
    }

    public var routeSamples: [TelemetryPointModel] {
        let sortedSamples = samples
            .filter(\.hasValidCoordinate)
            .sorted { $0.timestamp < $1.timestamp }

        var previousLatitude: Double?
        var previousLongitude: Double?
        return sortedSamples.filter { sample in
            defer {
                previousLatitude = sample.latitude
                previousLongitude = sample.longitude
            }
            return sample.latitude != previousLatitude || sample.longitude != previousLongitude
        }
    }
}
