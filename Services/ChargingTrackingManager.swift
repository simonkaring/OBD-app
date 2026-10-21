import Foundation
import Combine
import SwiftData
import CoreLocation

@MainActor
public final class ChargingTrackingManager: ObservableObject {
    @Published public private(set) var currentSession: ChargingSessionModel?
    @Published public private(set) var isRecordingSession: Bool = false
    @Published public private(set) var demoSessions: [ChargingSessionModel] = []
    @Published public private(set) var persistenceError: String?
    public private(set) var isDemoMode = false
    private var context: ModelContext? { isDemoMode ? nil : modelContext }

    public var modelContext: ModelContext?
    public let locationManager: TripLocationManager

    /// Consecutive non-charging snapshots required before an active session is closed.
    static let endSessionSnapshotThreshold = 3

    private var cancellables = Set<AnyCancellable>()
    private var lastSnapshotTime: Date?
    private var lastSaveTime: Date?
    private var nonChargingSnapshotCount = 0
    private var geocoder = CLGeocoder()
    /// Most recent curve point, used to throttle sample capture to meaningful changes.
    private var lastCurveSample: (timestamp: Date, socPct: Double)?
    static let maxCurveSamples = 720

    public init(locationManager: TripLocationManager = TripLocationManager()) {
        self.locationManager = locationManager
    }

    public func startSession(startSoc: Double = 0.0, locationName: String = "Charging Station") {
        guard currentSession == nil else { return }
        let lat = isDemoMode ? nil : locationManager.currentLocation?.coordinate.latitude
        let lon = isDemoMode ? nil : locationManager.currentLocation?.coordinate.longitude

        let validCoord: (lat: Double, lon: Double)? = {
            if let lat = lat, let lon = lon, (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) {
                return (lat, lon)
            }
            return nil
        }()

        let session = ChargingSessionModel(
            startTime: Date(),
            startSocPct: startSoc,
            locationName: locationName,
            latitude: validCoord?.lat,
            longitude: validCoord?.lon
        )
        self.currentSession = session
        self.isRecordingSession = true
        self.lastSnapshotTime = Date()
        self.lastSaveTime = Date()

        context?.insert(session)
        save()
        Haptics.impact()
        appendCurveSample(socPct: session.startSocPct, powerKW: 0, at: session.startTime)

        // Reverse-geocode location if coordinate is available. The completion runs
        // off the main actor, so it only captures Sendable values and re-enters the
        // actor with the session id instead of a non-Sendable SwiftData model.
        if let coord = validCoord {
            let clLocation = CLLocation(latitude: coord.lat, longitude: coord.lon)
            let sessionID = session.id
            geocoder.reverseGeocodeLocation(clLocation) { [weak self] placemarks, _ in
                guard let placemark = placemarks?.first else { return }
                var components: [String] = []
                if let name = placemark.name { components.append(name) } else if let street = placemark.thoroughfare { components.append(street) }
                if let locality = placemark.locality { components.append(locality) }
                let resolvedName = components.isEmpty ? "Charging Station" : components.joined(separator: ", ")
                Task { @MainActor [weak self] in
                    self?.applyGeocodedName(resolvedName, to: sessionID)
                }
            }
        }
    }

    private func applyGeocodedName(_ name: String, to sessionID: UUID) {
        guard let session = currentSession, session.id == sessionID else { return }
        session.locationName = name
        save()
    }

    @discardableResult
    public func stopSession(endSoc: Double? = nil) -> Bool {
        guard let session = currentSession else { return true }
        if session.endTime == nil {
            session.endTime = Date()
            if let endSoc { session.endSocPct = endSoc }
        }

        // Average power is only meaningful when energy was actually integrated. The old
        // `else` branch fell back to peak power, reporting a flat-out session for a
        // plug-in that delivered nothing.
        let durationHours = session.endTime!.timeIntervalSince(session.startTime) / 3600.0
        if durationHours > 0 && session.totalKWhDelivered > 0 {
            session.averagePowerKW = session.totalKWhDelivered / durationHours
        }

        guard save() else {
            Haptics.error()
            return false
        }
        if isDemoMode { demoSessions.insert(session, at: 0) }
        #if os(iOS)
        if !isDemoMode, session.totalKWhDelivered >= 0.5 || session.endSocPct - session.startSocPct >= 1 {
            NotificationService.shared.notifyChargingFinished(endSocPct: session.endSocPct)
        }
        #endif

        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil
        self.lastCurveSample = nil
        self.nonChargingSnapshotCount = 0
        Haptics.success()
        return true
    }

    @discardableResult
    public func setDemoMode(_ enabled: Bool, endSoc: Double) -> Bool {
        guard enabled != isDemoMode else { return true }
        guard stopSession(endSoc: endSoc) else { return false }
        geocoder.cancelGeocode()
        demoSessions.removeAll()
        isDemoMode = enabled
        if enabled { demoSessions = [Self.odenseChargingSession()] }
        return true
    }

    private static func odenseChargingSession() -> ChargingSessionModel {
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(-24 * 3600 + 11 * 3600 + 5 * 60)
        let session = ChargingSessionModel(
            startTime: start, startSocPct: 43,
            locationName: "Drejebænken 10, 5260 Odense", latitude: 55.352522, longitude: 10.421215)
        session.endTime = start.addingTimeInterval(40 * 60)
        session.endSocPct = 82
        session.totalKWhDelivered = 28
        session.peakPowerKW = 78
        session.averagePowerKW = 42
        let curve: [(soc: Double, power: Double)] = [
            (43, 78), (48, 77), (52, 72), (58, 64), (64, 55), (71, 44), (77, 30), (82, 14),
        ]
        session.samples = curve.enumerated().map { index, point in
            ChargingSampleModel(
                timestamp: start.addingTimeInterval(Double(index) * 5 * 60),
                socPct: point.soc,
                powerKW: point.power)
        }
        return session
    }

    @discardableResult
    public func save() -> Bool {
        do {
            try context?.save()
            persistenceError = nil
            return true
        } catch {
            persistenceError =
                "Charging history could not be saved: \(error.localizedDescription). Your pending changes are still in memory; retry saving before closing VoltLink."
            return false
        }
    }

    public func retrySaving() {
        if let session = currentSession, session.endTime != nil { stopSession(endSoc: session.endSocPct) } else { save() }
    }

    public func deleteSession(_ session: ChargingSessionModel) {
        let sessionID = session.id
        if currentSession?.id == sessionID {
            self.currentSession = nil
            self.isRecordingSession = false
            self.lastSnapshotTime = nil
        }
        demoSessions.removeAll { $0.id == sessionID }
        context?.delete(session)
        guard save() else { return }
        NotificationCenter.default.post(name: Notification.Name("DeleteChargingSessionNotification"), object: sessionID)
    }

    public func clearAllSessions() {
        geocoder.cancelGeocode()
        demoSessions.removeAll()
        nonChargingSnapshotCount = 0
        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil

        if let context {
            do {
                let allSessions = try context.fetch(FetchDescriptor<ChargingSessionModel>())
                for s in allSessions {
                    context.delete(s)
                }
                save()
            } catch {
                persistenceError = "Could not load charging sessions for deletion: \(error.localizedDescription)"
            }
        }
        NotificationCenter.default.post(name: Notification.Name("ClearSampleChargingSessions"), object: nil)
    }

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot) {
        // The vehicle manager resolves explicit status and speed validity once for all consumers.
        let chargingPower = max(0, telemetry.chargePowerKW)
        let isActivelyCharging = telemetry.isCharging && (!telemetry.hasFreshSpeed || telemetry.speedKmH < 1.0)

        if isRecordingSession {
            if isActivelyCharging {
                nonChargingSnapshotCount = 0
                recordSnapshot(telemetry, chargingPower: chargingPower)
            } else {
                lastSnapshotTime = nil
                // Hysteresis: a single dropout (a missed poll, a CP handshake pause, the
                // charger tapering through the threshold) used to end the session and split
                // one charge into several fragments. Require a sustained gap instead.
                nonChargingSnapshotCount += 1
                if nonChargingSnapshotCount >= Self.endSessionSnapshotThreshold {
                    stopSession(endSoc: telemetry.stateOfChargePct)
                }
            }
        } else {
            if isActivelyCharging {
                nonChargingSnapshotCount = 0
                startSession(startSoc: telemetry.stateOfChargePct)
                recordSnapshot(telemetry, chargingPower: chargingPower)
            }
        }
    }

    public func recordSnapshot(_ telemetry: TelemetrySnapshot, chargingPower: Double) {
        guard let session = currentSession, session.endTime == nil else { return }
        let now = Date()
        let dtHours: Double
        if let last = lastSnapshotTime {
            let interval = now.timeIntervalSince(last)
            dtHours = (interval > 0 && interval < 300) ? (interval / 3600.0) : 0.0
        } else {
            dtHours = 0.0
        }
        lastSnapshotTime = now

        if chargingPower > session.peakPowerKW {
            session.peakPowerKW = chargingPower
        }

        if dtHours > 0 && chargingPower > 0 {
            session.totalKWhDelivered += chargingPower * dtHours
        }

        if telemetry.stateOfChargePct > 0 {
            session.endSocPct = telemetry.stateOfChargePct
        }
        appendCurveSample(socPct: telemetry.stateOfChargePct, powerKW: chargingPower, at: now)
        if let lastSaveTime, now.timeIntervalSince(lastSaveTime) >= 30 {
            save()
            self.lastSaveTime = now
        }
    }

    /// Adds at most one point per percent of SOC or minute, whichever comes first, so a
    /// long session stores a readable curve without one row per poll cycle.
    private func appendCurveSample(socPct: Double, powerKW: Double, at date: Date) {
        guard let session = currentSession, session.endTime == nil, socPct.isFinite, socPct > 0 else { return }
        guard session.samples.count < Self.maxCurveSamples else { return }
        if let last = lastCurveSample {
            let socChanged = abs(socPct - last.socPct) >= 1
            let timeElapsed = date.timeIntervalSince(last.timestamp) >= 60
            guard socChanged || timeElapsed else { return }
        }
        let sample = ChargingSampleModel(timestamp: date, socPct: socPct, powerKW: max(0, powerKW))
        session.samples.append(sample)
        lastCurveSample = (date, socPct)
    }
}
