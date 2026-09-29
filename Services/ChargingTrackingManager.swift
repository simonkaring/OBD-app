import Foundation
import Combine
import SwiftData
import CoreLocation

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

        // Reverse-geocode location if coordinate is available
        if let coord = validCoord {
            let clLocation = CLLocation(latitude: coord.lat, longitude: coord.lon)
            geocoder.reverseGeocodeLocation(clLocation) { [weak self, weak session] placemarks, _ in
                guard let self = self, let session = session else { return }
                if let placemark = placemarks?.first {
                    var components: [String] = []
                    if let name = placemark.name { components.append(name) }
                    else if let street = placemark.thoroughfare { components.append(street) }
                    if let locality = placemark.locality { components.append(locality) }

                    let resolvedName = components.isEmpty ? "Charging Station" : components.joined(separator: ", ")
                    DispatchQueue.main.async {
                        session.locationName = resolvedName
                        self.save()
                    }
                }
            }
        }
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

        guard save() else { return false }
        if isDemoMode { demoSessions.insert(session, at: 0) }

        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil
        self.nonChargingSnapshotCount = 0
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
        let session = ChargingSessionModel(startTime: start, startSocPct: 43,
            locationName: "Drejebænken 10, 5260 Odense", latitude: 55.352522, longitude: 10.421215)
        session.endTime = start.addingTimeInterval(40 * 60)
        session.endSocPct = 82
        session.totalKWhDelivered = 28
        session.peakPowerKW = 78
        session.averagePowerKW = 42
        return session
    }

    @discardableResult
    public func save() -> Bool {
        do {
            try context?.save()
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Charging history could not be saved: \(error.localizedDescription). Your pending changes are still in memory; retry saving before closing VoltLink."
            return false
        }
    }

    public func retrySaving() {
        if let session = currentSession, session.endTime != nil { stopSession(endSoc: session.endSocPct) }
        else { save() }
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
        if let lastSaveTime, now.timeIntervalSince(lastSaveTime) >= 30 {
            save()
            self.lastSaveTime = now
        }
    }
}
