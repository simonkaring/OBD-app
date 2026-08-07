import Foundation
import Combine
import SwiftData

public final class TripTrackingManager: ObservableObject {
    @Published public private(set) var currentTrip: TripModel?
    @Published public private(set) var isRecordingTrip: Bool = false

    @Published public var isAutoTripEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoTripEnabled, forKey: "isAutoTripEnabled")
        }
    }

    @Published public var autoStopDelaySeconds: Int {
        didSet {
            UserDefaults.standard.set(autoStopDelaySeconds, forKey: "autoStopDelaySeconds")
        }
    }

    @Published public private(set) var stationarySecondsRemaining: Int? = nil

    private var cancellables = Set<AnyCancellable>()
    private let locationManager = TripLocationManager()
    private var stationaryStartDate: Date? = nil

    public init() {
        let savedAuto = UserDefaults.standard.object(forKey: "isAutoTripEnabled") as? Bool ?? true
        let savedDelay = UserDefaults.standard.integer(forKey: "autoStopDelaySeconds")
        self.isAutoTripEnabled = savedAuto
        self.autoStopDelaySeconds = savedDelay > 0 ? savedDelay : 120
    }

    public func startTrip(startSoc: Double = 80.0, vehicleName: String = "Mercedes EQA 250") {
        let trip = TripModel(startTime: Date(), distanceKm: 0.0, startSocPct: startSoc, vehicleName: vehicleName)
        self.currentTrip = trip
        self.isRecordingTrip = true
        self.stationaryStartDate = nil
        self.stationarySecondsRemaining = nil
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
        self.stationaryStartDate = nil
        self.stationarySecondsRemaining = nil
    }

    public func clearAllTrips() {
        self.currentTrip = nil
        self.isRecordingTrip = false
        self.stationaryStartDate = nil
        self.stationarySecondsRemaining = nil
        NotificationCenter.default.post(name: Notification.Name("ClearSampleTrips"), object: nil)
    }

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot, vehicleName: String = "Mercedes EQA 250", modelContext: ModelContext? = nil) {
        if isRecordingTrip {
            recordSnapshot(telemetry)

            if isAutoTripEnabled {
                if telemetry.speedKmH < 1.0 || telemetry.isCharging {
                    if stationaryStartDate == nil {
                        stationaryStartDate = Date()
                    }
                    let elapsed = Int(Date().timeIntervalSince(stationaryStartDate!))
                    let remaining = max(0, autoStopDelaySeconds - elapsed)
                    self.stationarySecondsRemaining = remaining

                    if elapsed >= autoStopDelaySeconds {
                        stopTrip(endSoc: telemetry.stateOfChargePct, modelContext: modelContext)
                    }
                } else {
                    stationaryStartDate = nil
                    stationarySecondsRemaining = nil
                }
            }
        } else if isAutoTripEnabled {
            stationaryStartDate = nil
            stationarySecondsRemaining = nil

            if telemetry.speedKmH >= 5.0 {
                startTrip(startSoc: telemetry.stateOfChargePct, vehicleName: vehicleName)
                recordSnapshot(telemetry)
            }
        }
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
