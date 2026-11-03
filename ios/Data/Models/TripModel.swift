import Foundation
import SwiftData

/// One GPS/telemetry point on a recorded trip.
///
/// Every stored property carries its default at the declaration, and `trip` is the optional
/// inverse of `TripModel.samples`: CloudKit rejects attributes without defaults and
/// relationships that are not optional, so these are the shapes the synced store requires.
@Model
public final class TelemetryPointModel {
    public var timestamp: Date = Date()
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var speedKmH: Double = 0
    public var powerKW: Double = 0
    public var socPct: Double = 0
    public var batteryTempC: Double = 25
    public var trip: TripModel?

    public init(
        timestamp: Date = Date(), latitude: Double = 0.0, longitude: Double = 0.0, speedKmH: Double = 0.0, powerKW: Double = 0.0, socPct: Double = 0.0,
        batteryTempC: Double = 25.0
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speedKmH = speedKmH
        self.powerKW = powerKW
        self.socPct = socPct
        self.batteryTempC = batteryTempC
    }

    public var hasValidCoordinate: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && !(latitude == 0 && longitude == 0)
    }
}

@Model
public final class TripModel {
    public var id: UUID = UUID()
    public var startTime: Date = Date()
    public var endTime: Date?
    public var distanceKm: Double = 0
    public var startSocPct: Double = 0
    public var endSocPct: Double = 0
    public var totalKWhUsed: Double = 0
    /// Nil for older recordings which did not track recovered energy.
    public var totalKWhRecovered: Double?
    public var averageSpeedKmH: Double = 0
    public var maxPowerKW: Double = 0
    public var maxRegenKW: Double = 0
    public var vehicleName: String = "Vehicle"

    /// Optional so the store can sync with CloudKit; read it through `samplePoints` unless
    /// you need to distinguish "no samples" from "relationship not loaded".
    @Relationship(deleteRule: .cascade, inverse: \TelemetryPointModel.trip)
    public var samples: [TelemetryPointModel]? = []

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

    /// Non-optional route for read-only callers.
    public var samplePoints: [TelemetryPointModel] {
        samples ?? []
    }

    public var efficiencyKWhPer100Km: Double {
        guard distanceKm > 0.1 else { return 0.0 }
        return ((totalKWhUsed - (totalKWhRecovered ?? 0)) / distanceKm) * 100.0
    }

    public var computedAverageSpeedKmH: Double {
        let speedSamples = samplePoints.lazy.map(\.speedKmH).filter { $0.isFinite }
        var count = 0
        var sum = 0.0
        for s in speedSamples {
            sum += s
            count += 1
        }
        if count > 0 {
            return sum / Double(count)
        }
        if averageSpeedKmH > 0 {
            return averageSpeedKmH
        }
        guard let endTime, distanceKm > 0 else { return 0.0 }
        let hours = endTime.timeIntervalSince(startTime) / 3600.0
        return hours > 0 ? (distanceKm / hours) : 0.0
    }

    public var averagePowerKW: Double {
        let powerSamples = samplePoints.lazy.map(\.powerKW).filter { $0.isFinite }
        var count = 0
        var sum = 0.0
        for p in powerSamples {
            sum += p
            count += 1
        }
        if count > 0 {
            return sum / Double(count)
        }
        guard let endTime, (totalKWhUsed > 0 || (totalKWhRecovered ?? 0) > 0) else { return 0.0 }
        let hours = endTime.timeIntervalSince(startTime) / 3600.0
        return hours > 0 ? ((totalKWhUsed - (totalKWhRecovered ?? 0)) / hours) : 0.0
    }

    public var routeSamples: [TelemetryPointModel] {
        let sortedSamples =
            samplePoints
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
