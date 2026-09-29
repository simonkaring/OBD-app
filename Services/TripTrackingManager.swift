import Foundation
import Combine
import SwiftData
import CoreLocation

public final class TripTrackingManager: ObservableObject {
    @Published public private(set) var currentTrip: TripModel?
    @Published public private(set) var isRecordingTrip: Bool = false
    @Published public private(set) var averageConsumption: Double?
    private var hasCompleteEnergyData = true
    @Published public private(set) var demoTrips: [TripModel] = []
    @Published public private(set) var persistenceError: String?
    public private(set) var isDemoMode = false
    private var context: ModelContext? { isDemoMode ? nil : modelContext }

    @Published public var isAutoTripEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoTripEnabled, forKey: "isAutoTripEnabled")
            if !isAutoTripEnabled { resetStationaryTimer() }
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
    private var lastStoredSampleTime: Date?
    private var lastSaveTime: Date?
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

    public func startTrip(startSoc: Double = 80.0, vehicleName: String = "Vehicle") {
        guard currentTrip == nil else { return }
        let trip = TripModel(startTime: Date(), distanceKm: 0.0, startSocPct: startSoc, vehicleName: vehicleName)
        self.currentTrip = trip
        self.isRecordingTrip = true
        self.averageConsumption = nil
        self.hasCompleteEnergyData = true
        self.lastSampleTime = nil
        self.lastStoredSampleTime = nil
        self.lastSaveTime = Date()
        resetStationaryTimer()
        if !isDemoMode { locationManager.startTracking() }
        context?.insert(trip)
        save()
    }

    @discardableResult
    public func stopTrip(endSoc: Double = 75.0) -> Bool {
        guard let trip = currentTrip else { return true }
        if trip.endTime == nil {
            trip.endTime = Date()
            trip.endSocPct = endSoc
        }
        trip.averageSpeedKmH = trip.computedAverageSpeedKmH
        locationManager.stopTracking()
        resetStationaryTimer()
        guard save() else { return false }
        if isDemoMode { demoTrips.insert(trip, at: 0) }

        self.currentTrip = nil
        self.isRecordingTrip = false
        self.averageConsumption = nil
        self.lastSampleTime = nil
        resetStationaryTimer()
        return true
    }

    @discardableResult
    public func setDemoMode(_ enabled: Bool, endSoc: Double) -> Bool {
        guard enabled != isDemoMode else { return true }
        guard stopTrip(endSoc: endSoc) else { return false }
        demoTrips.removeAll()
        isDemoMode = enabled
        if enabled { demoTrips = [Self.copenhagenToOdenseTrip()] }
        return true
    }

    private static func copenhagenToOdenseTrip() -> TripModel {
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(-24 * 3600 + 9 * 3600)
        let trip = TripModel(startTime: start, distanceKm: 158.9, startSocPct: 82, vehicleName: "Mercedes-Benz EQA 250")
        trip.endTime = start.addingTimeInterval(110 * 60)
        trip.endSocPct = 43
        trip.totalKWhUsed = 30.2
        trip.totalKWhRecovered = 1.2
        trip.averageSpeedKmH = 86.7
        trip.maxPowerKW = 95
        trip.maxRegenKW = -28

        // Road waypoints from Copenhagen via Storebælt to Drejebænken 10, Odense.
        let route: [(Double, Double)] = [
            (55.676328, 12.569312), (55.665112, 12.557955), (55.659578, 12.491748),
            (55.652789, 12.488200), (55.641374, 12.416469), (55.637247, 12.336490),
            (55.613688, 12.324044), (55.568750, 12.238654), (55.535238, 12.199289),
            (55.488406, 12.167190), (55.480124, 12.148200), (55.478959, 12.100264),
            (55.458172, 11.992889), (55.453122, 11.864208), (55.457770, 11.760357),
            (55.447544, 11.654629), (55.460062, 11.578230), (55.458852, 11.553223),
            (55.436707, 11.495930), (55.427194, 11.428617), (55.405410, 11.401946),
            (55.367698, 11.287113), (55.360807, 11.168869), (55.349104, 11.133800),
            (55.334694, 10.979746), (55.298549, 10.844916), (55.308771, 10.812342),
            (55.328517, 10.802856), (55.333795, 10.790527), (55.331931, 10.737965),
            (55.344188, 10.629489), (55.365613, 10.525311), (55.348532, 10.450371),
            (55.352479, 10.421264)
        ]
        trip.samples = route.enumerated().map { index, coordinate in
            let progress = Double(index) / Double(route.count - 1)
            return TelemetryPointModel(
                timestamp: start.addingTimeInterval(110 * 60 * progress),
                latitude: coordinate.0, longitude: coordinate.1,
                speedKmH: index == 0 || index == route.count - 1 ? 0 : (index < 8 || index > 29 ? 55 : 110),
                powerKW: index == 0 || index == route.count - 1 ? 0 : (index % 7 == 0 ? -18 : 23),
                socPct: 82 - 39 * progress, batteryTempC: 24 + 5 * progress
            )
        }
        return trip
    }

    @discardableResult
    public func save() -> Bool {
        do {
            try context?.save()
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Trip history could not be saved: \(error.localizedDescription). Your pending changes are still in memory; retry saving before closing VoltLink."
            return false
        }
    }

    public func retrySaving() {
        if let trip = currentTrip, trip.endTime != nil { stopTrip(endSoc: trip.endSocPct) }
        else { save() }
    }

    public func deleteTrip(_ trip: TripModel) {
        let tripID = trip.id
        if currentTrip?.id == tripID {
            locationManager.stopTracking()
            lastSampleTime = nil
            self.currentTrip = nil
            self.isRecordingTrip = false
            self.averageConsumption = nil
            resetStationaryTimer()
        }
        demoTrips.removeAll { $0.id == tripID }
        context?.delete(trip)
        guard save() else { return }
        NotificationCenter.default.post(name: Notification.Name("DeleteTripNotification"), object: tripID)
    }

    public func clearAllTrips() {
        locationManager.stopTracking()
        lastSampleTime = nil
        demoTrips.removeAll()
        self.currentTrip = nil
        self.isRecordingTrip = false
        self.averageConsumption = nil
        resetStationaryTimer()

        if let context {
            do {
                let allTrips = try context.fetch(FetchDescriptor<TripModel>())
                for trip in allTrips {
                    context.delete(trip)
                }
                save()
            } catch {
                persistenceError = "Could not load trips for deletion: \(error.localizedDescription)"
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

        let context = self.context
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
            if let olderRecovered = older.totalKWhRecovered, let newerRecovered = newer.totalKWhRecovered {
                older.totalKWhRecovered = olderRecovered + newerRecovered
            } else {
                older.totalKWhRecovered = nil
            }
            older.maxPowerKW = max(older.maxPowerKW, newer.maxPowerKW)
            older.maxRegenKW = min(older.maxRegenKW, newer.maxRegenKW)
            older.endTime = newer.endTime
            older.endSocPct = newer.endSocPct
            older.averageSpeedKmH = older.computedAverageSpeedKmH
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
                demoTrips.removeAll { $0.id == newer.id }
            }
        } catch {
            if previousUndoManager != nil { undoManager.disableUndoRegistration() }
            undoManager.undoNestedGroup()
            // Refresh SwiftData's registration after undoing Core Data's deletion.
            context?.insert(newer)
            context?.processPendingChanges()
            if previousUndoManager != nil { undoManager.enableUndoRegistration() }
            persistenceError = "Failed to merge trips: \(error.localizedDescription)"
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
                guard let self = self, let start = self.stationaryStartDate, self.isRecordingTrip, self.isAutoTripEnabled else { return }
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

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot, vehicleName: String = "Vehicle", hasPowerData: Bool = true, requiresPowerForAutoStart: Bool = false) {
        latestSoc = telemetry.stateOfChargePct

        if isRecordingTrip {
            recordSnapshot(telemetry, hasPowerData: hasPowerData)

            if isAutoTripEnabled {
                if telemetry.speedKmH < 1.0 || telemetry.isCharging {
                    startStationaryCountdownIfNeeded()
                } else {
                    resetStationaryTimer()
                }
            }
        } else if isAutoTripEnabled {
            resetStationaryTimer()

            if telemetry.speedKmH >= 5.0 && (hasPowerData || !requiresPowerForAutoStart) {
                startTrip(startSoc: telemetry.stateOfChargePct, vehicleName: vehicleName)
                recordSnapshot(telemetry, hasPowerData: hasPowerData)
            }
        }
    }

    public func recordSnapshot(_ telemetry: TelemetrySnapshot, at now: Date = .now, hasPowerData: Bool = true) {
        guard let trip = currentTrip, trip.endTime == nil else { return }
        // Integrate every update, but persist route/chart points at one-second resolution.
        // This keeps energy independent of the number of PIDs returned by a response.
        if let last = lastSampleTime {
            let interval = now.timeIntervalSince(last)
            if interval > 0, interval < 300 {
                if !telemetry.isCharging {
                    if !hasPowerData { hasCompleteEnergyData = false }
                    if hasPowerData && telemetry.powerKW > 0 {
                        trip.totalKWhUsed += telemetry.powerKW * interval / 3600
                    } else if hasPowerData && telemetry.powerKW < 0 {
                        if telemetry.hasFreshSpeed && telemetry.speedKmH >= 1 {
                            trip.totalKWhRecovered = (trip.totalKWhRecovered ?? 0) - telemetry.powerKW * interval / 3600
                        } else if !telemetry.hasFreshSpeed {
                            hasCompleteEnergyData = false
                        }
                    }
                }
                if isDemoMode { trip.distanceKm += telemetry.speedKmH * interval / 3600 }
            } else if interval >= 300 {
                hasCompleteEnergyData = false
            }
        }
        lastSampleTime = now
        if !isDemoMode { trip.distanceKm = locationManager.totalDistanceMeters / 1000 }
        averageConsumption = hasCompleteEnergyData && hasPowerData && trip.distanceKm > 0.1 ? trip.efficiencyKWhPer100Km : nil
        trip.endSocPct = telemetry.stateOfChargePct
        trip.maxPowerKW = max(trip.maxPowerKW, telemetry.powerKW)
        trip.maxRegenKW = min(trip.maxRegenKW, telemetry.powerKW)
        if let lastSaveTime, now.timeIntervalSince(lastSaveTime) >= 30 {
            save()
            self.lastSaveTime = now
        }
        guard lastStoredSampleTime.map({ now.timeIntervalSince($0) >= 1 }) ?? true else { return }
        lastStoredSampleTime = now
        // `TelemetryPointModel` stores non-optional coordinates (making them optional is a
        // SwiftData schema change), so (0, 0) stays the "no fix" sentinel — but only write
        // it when there genuinely is no usable fix, and let `hasValidCoordinate` /
        // `routeSamples` filter those points out of the map.
        let coordinate = isDemoMode ? nil : locationManager.currentLocation?.coordinate
        let hasFix = coordinate.map { (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) && !($0.latitude == 0 && $0.longitude == 0) } ?? false
        let lat = hasFix ? coordinate!.latitude : 0.0
        let lon = hasFix ? coordinate!.longitude : 0.0

        let sample = TelemetryPointModel(
            timestamp: now,
            latitude: lat,
            longitude: lon,
            speedKmH: telemetry.speedKmH,
            powerKW: telemetry.powerKW,
            socPct: telemetry.stateOfChargePct,
            batteryTempC: telemetry.batteryTempC
        )
        trip.samples.append(sample)
    }

    public func telemetryForDisplay(_ snapshot: TelemetrySnapshot) -> TelemetrySnapshot {
        var displayed = snapshot
        displayed.tripAverageConsumption = averageConsumption
        return displayed
    }
}
