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
    /// Timestamp of the previous recorded sample, used to integrate energy over the real
    /// elapsed interval instead of an assumed fixed polling period.
    private var lastSampleTime: Date? = nil
    /// Most recent SoC seen by `processTelemetrySnapshot`, so the auto-stop timer can read
    /// the value at fire time rather than the one captured when the countdown started.
    private var latestSoc: Double = 0.0

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
        self.lastSampleTime = nil
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
        self.lastSampleTime = nil
        resetStationaryTimer()
    }

    public func deleteTrip(_ trip: TripModel) {
        let tripID = trip.id
        if currentTrip?.id == tripID {
            self.currentTrip = nil
            self.isRecordingTrip = false
            resetStationaryTimer()
        }
        modelContext?.delete(trip)
        do {
            try modelContext?.save()
        } catch {
            print("Failed to delete trip: \(error)")
            return
        }
        NotificationCenter.default.post(name: Notification.Name("DeleteTripNotification"), object: tripID)
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

        let context = modelContext
        // Flush earlier edits before grouping so a failed merge only undoes itself.
        context?.processPendingChanges()
        let previousUndoManager = context?.undoManager
        let undoManager = previousUndoManager ?? UndoManager()
        if previousUndoManager == nil {
            context?.undoManager = undoManager
        }
        defer {
            if previousUndoManager == nil { context?.undoManager = nil }
        }

        // Copy values instead of reparenting: SwiftData can lose a moved sample's
        // relationship or cascade-delete it. Copies and deletion commit in one save.
        let copies = newer.samples.map { sample in
            TelemetryPointModel(timestamp: sample.timestamp,
                                latitude: sample.latitude, longitude: sample.longitude,
                                speedKmH: sample.speedKmH, powerKW: sample.powerKW,
                                socPct: sample.socPct, batteryTempC: sample.batteryTempC)
        }

        let applyMerge = {
            older.samples.append(contentsOf: copies)
            older.distanceKm += newer.distanceKm
            older.totalKWhUsed += newer.totalKWhUsed
            older.maxPowerKW = max(older.maxPowerKW, newer.maxPowerKW)
            older.maxRegenKW = min(older.maxRegenKW, newer.maxRegenKW)
            older.endTime = newer.endTime
            older.endSocPct = newer.endSocPct
            context?.delete(newer)
        }

        do {
            if let context {
                let groupingLevel = undoManager.groupingLevel
                undoManager.beginUndoGrouping()
                applyMerge()
                context.processPendingChanges()
                // Processing pending changes may already close the outermost group.
                if undoManager.groupingLevel > groupingLevel { undoManager.endUndoGrouping() }
                try context.save()
            } else {
                applyMerge()
            }
        } catch {
            if previousUndoManager != nil { undoManager.disableUndoRegistration() }
            undoManager.undoNestedGroup()
            // Refresh SwiftData's registration after undoing Core Data's deletion.
            context?.insert(newer)
            context?.processPendingChanges()
            if previousUndoManager != nil { undoManager.enableUndoRegistration() }
            print("Failed to merge trips: \(error)")
        }
    }

    private func resetStationaryTimer() {
        stationaryTimer?.invalidate()
        stationaryTimer = nil
        stationaryStartDate = nil
        stationarySecondsRemaining = nil
    }

    private func startStationaryCountdownIfNeeded() {
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
                    // Read the SoC as of now; the value at countdown start is minutes stale.
                    self.stopTrip(endSoc: self.latestSoc)
                }
            }
        }

        if elapsed >= autoStopDelaySeconds {
            stopTrip(endSoc: latestSoc)
        }
    }

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot, vehicleName: String = "Mercedes EQA 250") {
        latestSoc = telemetry.stateOfChargePct

        if isRecordingTrip {
            recordSnapshot(telemetry)

            if isAutoTripEnabled {
                if telemetry.speedKmH < 1.0 || telemetry.isCharging {
                    startStationaryCountdownIfNeeded()
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
        // `TelemetryPointModel` stores non-optional coordinates (making them optional is a
        // SwiftData schema change), so (0, 0) stays the "no fix" sentinel — but only write
        // it when there genuinely is no usable fix, and let `hasValidCoordinate` /
        // `routeSamples` filter those points out of the map.
        let coordinate = locationManager.currentLocation?.coordinate
        let hasFix = coordinate.map { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && !($0.latitude == 0 && $0.longitude == 0) } ?? false
        let lat = hasFix ? coordinate!.latitude : 0.0
        let lon = hasFix ? coordinate!.longitude : 0.0

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

        // Accumulate energy consumption over the *measured* interval. The previous
        // hardcoded 0.5 s assumption silently mis-scaled every trip's kWh total, since the
        // poll loop's real cadence depends on adapter latency and command round-robin.
        let now = sample.timestamp
        if let last = lastSampleTime {
            let interval = now.timeIntervalSince(last)
            if interval > 0, interval < 300, telemetry.powerKW > 0 {
                trip.totalKWhUsed += telemetry.powerKW * (interval / 3600.0)
            }
        }
        lastSampleTime = now
    }
}
