import Foundation
import Combine
import SwiftData
import CoreLocation

public final class ChargingTrackingManager: ObservableObject {
    @Published public private(set) var currentSession: ChargingSessionModel?
    @Published public private(set) var isRecordingSession: Bool = false

    public var modelContext: ModelContext?
    public let locationManager: TripLocationManager

    private var cancellables = Set<AnyCancellable>()
    private var lastSnapshotTime: Date?
    private var geocoder = CLGeocoder()

    public init(locationManager: TripLocationManager = TripLocationManager()) {
        self.locationManager = locationManager
    }

    public func startSession(startSoc: Double = 0.0, locationName: String = "Charging Station") {
        let lat = locationManager.currentLocation?.coordinate.latitude
        let lon = locationManager.currentLocation?.coordinate.longitude
        
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

        modelContext?.insert(session)
        try? modelContext?.save()

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
                        try? self.modelContext?.save()
                    }
                }
            }
        }
    }

    public func stopSession(endSoc: Double? = nil) {
        guard let session = currentSession else { return }
        session.endTime = Date()
        if let endSoc = endSoc {
            session.endSocPct = endSoc
        }
        
        let durationHours = session.endTime!.timeIntervalSince(session.startTime) / 3600.0
        if durationHours > 0 && session.totalKWhDelivered > 0 {
            session.averagePowerKW = session.totalKWhDelivered / durationHours
        } else if session.peakPowerKW > 0 {
            session.averagePowerKW = session.peakPowerKW
        }

        try? modelContext?.save()

        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil
    }

    public func deleteSession(_ session: ChargingSessionModel) {
        if currentSession?.id == session.id {
            self.currentSession = nil
            self.isRecordingSession = false
            self.lastSnapshotTime = nil
        }
        modelContext?.delete(session)
        try? modelContext?.save()
        NotificationCenter.default.post(name: Notification.Name("DeleteChargingSessionNotification"), object: session.id)
    }

    public func clearAllSessions() {
        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil

        if let context = modelContext {
            if let allSessions = try? context.fetch(FetchDescriptor<ChargingSessionModel>()) {
                for s in allSessions {
                    context.delete(s)
                }
                try? context.save()
            }
        }
        NotificationCenter.default.post(name: Notification.Name("ClearSampleChargingSessions"), object: nil)
    }

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot) {
        let isStationary = telemetry.speedKmH < 1.0
        let chargingPower = telemetry.chargePowerKW > 0 ? telemetry.chargePowerKW : (telemetry.powerKW < -0.5 ? abs(telemetry.powerKW) : 0.0)
        let isActivelyCharging = isStationary && (telemetry.isCharging || chargingPower > 0.5)

        if isRecordingSession {
            if isActivelyCharging {
                recordSnapshot(telemetry, chargingPower: chargingPower)
            } else {
                stopSession(endSoc: telemetry.stateOfChargePct)
            }
        } else {
            if isActivelyCharging {
                startSession(startSoc: telemetry.stateOfChargePct)
                recordSnapshot(telemetry, chargingPower: chargingPower)
            }
        }
    }

    public func recordSnapshot(_ telemetry: TelemetrySnapshot, chargingPower: Double) {
        guard let session = currentSession else { return }
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
    }
}
