import Foundation
import Combine
import SwiftData
import CoreLocation

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
    @Published public private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    public var modelContext: ModelContext?

    /// A trip resumed via `merge(_:into:)` within this window of a prior trip's end is
    /// eligible for merging; the merge itself is user-triggered, never automatic.
    public static let mergeWindow: TimeInterval = 30 * 60

    private var cancellables = Set<AnyCancellable>()
    public let locationManager: TripLocationManager
    private var stationaryStartDate: Date? = nil
    private var stationaryTimer: Timer? = nil

    public init(locationManager: TripLocationManager = TripLocationManager()) {
        self.locationManager = locationManager
        let savedAuto = UserDefaults.standard.object(forKey: "isAutoTripEnabled") as? Bool ?? true
        let savedDelay = UserDefaults.standard.integer(forKey: "autoStopDelaySeconds")
        self.isAutoTripEnabled = savedAuto
        self.autoStopDelaySeconds = savedDelay > 0 ? savedDelay : 120
        self.locationAuthorizationStatus = locationManager.authorizationStatus

        locationManager.$authorizationStatus
            .sink { [weak self] in self?.locationAuthorizationStatus = $0 }
            .store(in: &cancellables)
    }

    public func requestLocationAuthorization() {
        locationManager.requestAuthorization()
    }

    public func requestBackgroundLocationAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    public func startTrip(startSoc: Double = 80.0, vehicleName: String = "Mercedes EQA 250") {
        let trip = TripModel(startTime: Date(), distanceKm: 0.0, startSocPct: startSoc, vehicleName: vehicleName)
        self.currentTrip = trip
        self.isRecordingTrip = true
        resetStationaryTimer()
        locationManager.startTracking()
        modelContext?.insert(trip)
        try? modelContext?.save()
    }

    public func stopTrip(endSoc: Double = 75.0) {
        guard let trip = currentTrip else { return }
        trip.endTime = Date()
        trip.endSocPct = endSoc
        locationManager.stopTracking()
        try? modelContext?.save()

        self.currentTrip = nil
        self.isRecordingTrip = false
        resetStationaryTimer()
    }

    public func deleteTrip(_ trip: TripModel) {
        if currentTrip?.id == trip.id {
            self.currentTrip = nil
            self.isRecordingTrip = false
            resetStationaryTimer()
        }
        modelContext?.delete(trip)
        try? modelContext?.save()
        NotificationCenter.default.post(name: Notification.Name("DeleteTripNotification"), object: trip.id)
    }

    public func clearAllTrips() {
        self.currentTrip = nil
        self.isRecordingTrip = false
        resetStationaryTimer()

        if let context = modelContext {
            if let allTrips = try? context.fetch(FetchDescriptor<TripModel>()) {
                for trip in allTrips {
                    context.delete(trip)
                }
                try? context.save()
            }
        }
        NotificationCenter.default.post(name: Notification.Name("ClearSampleTrips"), object: nil)
    }

    /// Trips always record separately; merging is an explicit user action from the trip list,
    /// never automatic, so a short stop (e.g. a fuel/charging break) doesn't silently vanish.
    public func canMerge(_ newer: TripModel, into older: TripModel) -> Bool {
        guard let olderEnd = older.endTime, newer.endTime != nil, newer.id != older.id else { return false }
        let gap = newer.startTime.timeIntervalSince(olderEnd)
        return gap >= 0 && gap <= Self.mergeWindow
    }

    public func merge(_ newer: TripModel, into older: TripModel) {
        guard canMerge(newer, into: older) else { return }

        older.samples.append(contentsOf: newer.samples)
        older.distanceKm += newer.distanceKm
        older.totalKWhUsed += newer.totalKWhUsed
        older.maxPowerKW = max(older.maxPowerKW, newer.maxPowerKW)
        older.maxRegenKW = min(older.maxRegenKW, newer.maxRegenKW)
        older.endTime = newer.endTime
        older.endSocPct = newer.endSocPct

        modelContext?.delete(newer)
        try? modelContext?.save()
    }

    private func resetStationaryTimer() {
        stationaryTimer?.invalidate()
        stationaryTimer = nil
        stationaryStartDate = nil
        stationarySecondsRemaining = nil
    }

    private func startStationaryCountdownIfNeeded(lastSoc: Double) {
        if stationaryStartDate == nil {
            stationaryStartDate = Date()
        }

        let elapsed = Int(Date().timeIntervalSince(stationaryStartDate!))
        self.stationarySecondsRemaining = max(0, autoStopDelaySeconds - elapsed)

        if stationaryTimer == nil {
            stationaryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.stationaryStartDate, self.isRecordingTrip else { return }
                let currentElapsed = Int(Date().timeIntervalSince(start))
                let remaining = max(0, self.autoStopDelaySeconds - currentElapsed)
                self.stationarySecondsRemaining = remaining

                if currentElapsed >= self.autoStopDelaySeconds {
                    self.stopTrip(endSoc: lastSoc)
                }
            }
        }

        if elapsed >= autoStopDelaySeconds {
            stopTrip(endSoc: lastSoc)
        }
    }

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot, vehicleName: String = "Mercedes EQA 250") {
        if isRecordingTrip {
            recordSnapshot(telemetry)

            if isAutoTripEnabled {
                if telemetry.speedKmH < 1.0 || telemetry.isCharging {
                    startStationaryCountdownIfNeeded(lastSoc: telemetry.stateOfChargePct)
                } else {
                    resetStationaryTimer()
                }
            }
        } else if isAutoTripEnabled {
            resetStationaryTimer()

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
