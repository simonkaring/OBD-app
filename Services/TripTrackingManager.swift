import Foundation
import Combine
import SwiftData

public final class TripTrackingManager: ObservableObject {
    @Published public private(set) var currentTrip: TripModel?
    @Published public private(set) var isRecordingTrip: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let locationManager = TripLocationManager()

    public init() {}

    public func startTrip(startSoc: Double = 80.0, vehicleName: String = "Mercedes EQA 250") {
        let trip = TripModel(startTime: Date(), distanceKm: 0.0, startSocPct: startSoc, vehicleName: vehicleName)
        self.currentTrip = trip
        self.isRecordingTrip = true
        locationManager.startTracking()
    }

    public func stopTrip(endSoc: Double = 75.0, modelContext: ModelContext? = nil) {
        guard let trip = currentTrip else { return }
        trip.endTime = Date()
        trip.endSocPct = endSoc
        locationManager.stopTracking()

        if let context = modelContext {
            context.insert(trip)
            try? context.save()
        }

        self.currentTrip = nil
        self.isRecordingTrip = false
    }

    public func recordSnapshot(_ telemetry: TelemetrySnapshot) {
        guard let trip = currentTrip else { return }
        let lat = locationManager.currentLocation?.coordinate.latitude ?? 0.0
        let lon = locationManager.currentLocation?.coordinate.longitude ?? 0.0

        let sample = TelemetryPointModel(
            timestamp: Date(),
            latitude: lat,
            longitude: lon,
            speedKmH: telemetry.speedKmH,
            powerKW: telemetry.powerKW,
            socPct: telemetry.stateOfChargePct,
            batteryTempC: telemetry.batteryTempC
        )
        trip.samples.append(sample)
        trip.distanceKm = locationManager.totalDistanceMeters / 1000.0

        if telemetry.powerKW > trip.maxPowerKW { trip.maxPowerKW = telemetry.powerKW }
        if telemetry.powerKW < trip.maxRegenKW { trip.maxRegenKW = telemetry.powerKW }

        // Accumulate energy consumption: kW * (interval seconds / 3600)
        if telemetry.powerKW > 0 {
            trip.totalKWhUsed += (telemetry.powerKW * (0.5 / 3600.0))
        }
    }
}
