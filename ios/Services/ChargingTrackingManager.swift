import Foundation
import Combine
import SwiftData
import CoreLocation

@MainActor
public final class ChargingTrackingManager: ObservableObject {
    @Published public private(set) var currentSession: ChargingSessionModel?
    @Published public private(set) var isRecordingSession: Bool = false
    /// Live total for the active session. The SwiftData model is not observable, so this
    /// mirrors it for the Charging tab, which must show the same energy the Log persists.
    @Published public private(set) var liveEnergyKWh: Double = 0
    @Published public private(set) var demoSessions: [ChargingSessionModel] = []
    @Published public private(set) var persistenceError: String?
    public private(set) var isDemoMode = false
    private var context: ModelContext? { isDemoMode ? nil : modelContext }

    public var modelContext: ModelContext?
    public let locationManager: TripLocationManager

    /// Consecutive non-charging snapshots required before an active session is closed.
    static let endSessionSnapshotThreshold = 3
    /// Charging must be observed for this long before a session is recorded, so a regen
    /// pulse or a wheel-speed sample that still reads 0 km/h cannot open one. The start is
    /// backdated to the first observation, keeping the recorded duration and curve honest.
    static let startConfirmationSeconds: TimeInterval = 60
    /// A session shorter than this that also delivered almost no energy is discarded
    /// instead of persisted: it was a detection artifact, not a charge.
    static let minimumRetainedSessionDuration: TimeInterval = 60
    static let minimumRetainedSessionEnergyKWh: Double = 0.5

    private var cancellables = Set<AnyCancellable>()
    private var lastSnapshotTime: Date?
    private var lastSaveTime: Date?
    private var nonChargingSnapshotCount = 0
    /// First charging observation of a candidate session, awaiting confirmation.
    private var pendingChargeStart: (time: Date, soc: Double)?
    private var geocoder = CLGeocoder()
    /// Most recent curve point, used to throttle sample capture to meaningful changes.
    private var lastCurveSample: (timestamp: Date, socPct: Double)?
    /// Prevents the target-reached alert from repeating for every poll after the crossing.
    private var hasNotifiedChargeTarget = false
    static let maxCurveSamples = 720

    public init(locationManager: TripLocationManager = TripLocationManager()) {
        self.locationManager = locationManager
    }

    public func startSession(
        startSoc: Double = 0.0, locationName: String = "Charging Station", startedAt: Date = .now
    ) {
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
            startTime: startedAt,
            startSocPct: startSoc,
            locationName: locationName,
            latitude: validCoord?.lat,
            longitude: validCoord?.lon
        )
        self.currentSession = session
        self.isRecordingSession = true
        // Integration starts at the backdated start so the confirmation window's energy is
        // included in the first snapshot.
        self.lastSnapshotTime = startedAt
        self.lastSaveTime = Date()
        self.hasNotifiedChargeTarget = false
        self.nonChargingSnapshotCount = 0
        self.liveEnergyKWh = 0

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
    public func stopSession(endSoc: Double? = nil, at now: Date = .now) -> Bool {
        guard let session = currentSession else { return true }
        if session.endTime == nil {
            session.endTime = now
            if let endSoc { session.endSocPct = endSoc }
        }

        // Average power is only meaningful when energy was actually integrated. The old
        // `else` branch fell back to peak power, reporting a flat-out session for a
        // plug-in that delivered nothing.
        let durationHours = session.endTime!.timeIntervalSince(session.startTime) / 3600.0
        if durationHours > 0 && session.totalKWhDelivered > 0 {
            session.averagePowerKW = session.totalKWhDelivered / durationHours
        }

        // A detection artifact never becomes history, and never raises a notification.
        if !isDemoMode, Self.isTrivial(session) {
            guard discardTrivialSession(session) else {
                Haptics.error()
                return false
            }
            finishSessionState()
            return true
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

        finishSessionState()
        Haptics.success()
        return true
    }

    /// A session this short that delivered almost nothing cannot be a real charge.
    private static func isTrivial(_ session: ChargingSessionModel) -> Bool {
        guard let endTime = session.endTime else { return false }
        return endTime.timeIntervalSince(session.startTime) < minimumRetainedSessionDuration
            && session.totalKWhDelivered < minimumRetainedSessionEnergyKWh
    }

    private func discardTrivialSession(_ session: ChargingSessionModel) -> Bool {
        context?.delete(session)
        if save() { return true }
        context?.rollback()
        return false
    }

    private func finishSessionState() {
        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil
        self.lastCurveSample = nil
        self.hasNotifiedChargeTarget = false
        self.nonChargingSnapshotCount = 0
        self.pendingChargeStart = nil
        self.liveEnergyKWh = 0
    }

    @discardableResult
    public func setDemoMode(_ enabled: Bool, endSoc: Double) -> Bool {
        guard enabled != isDemoMode else { return true }
        guard stopSession(endSoc: endSoc) else { return false }
        geocoder.cancelGeocode()
        demoSessions.removeAll()
        pendingChargeStart = nil
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
        guard save() else {
            // Same as trips: do not leave the deletion queued for the next autosave.
            context?.rollback()
            return
        }
        NotificationCenter.default.post(name: Notification.Name("DeleteChargingSessionNotification"), object: sessionID)
    }

    public func clearAllSessions() {
        geocoder.cancelGeocode()
        demoSessions.removeAll()
        nonChargingSnapshotCount = 0
        pendingChargeStart = nil
        self.currentSession = nil
        self.isRecordingSession = false
        self.lastSnapshotTime = nil

        if let context {
            do {
                let allSessions = try context.fetch(FetchDescriptor<ChargingSessionModel>())
                for s in allSessions {
                    context.delete(s)
                }
                if !save() { context.rollback() }
            } catch {
                persistenceError = "Could not load charging sessions for deletion: \(error.localizedDescription)"
            }
        }
        NotificationCenter.default.post(name: Notification.Name("ClearSampleChargingSessions"), object: nil)
    }

    public func processTelemetrySnapshot(_ telemetry: TelemetrySnapshot, displayedSoc: Double? = nil, now: Date = .now) {
        // The vehicle manager resolves explicit status and speed validity once for all consumers.
        let chargingPower = max(0, telemetry.chargePowerKW)
        let isActivelyCharging = telemetry.isCharging && (!telemetry.hasFreshSpeed || telemetry.speedKmH < 1.0)

        if isRecordingSession {
            if isActivelyCharging {
                nonChargingSnapshotCount = 0
                recordSnapshot(telemetry, chargingPower: chargingPower, displayedSoc: displayedSoc, at: now)
            } else {
                lastSnapshotTime = nil
                // Hysteresis: a single dropout (a missed poll, a CP handshake pause, the
                // charger tapering through the threshold) used to end the session and split
                // one charge into several fragments. Require a sustained gap instead.
                nonChargingSnapshotCount += 1
                if nonChargingSnapshotCount >= Self.endSessionSnapshotThreshold {
                    stopSession(endSoc: telemetry.stateOfChargePct, at: now)
                }
            }
            return
        }

        guard isActivelyCharging else {
            pendingChargeStart = nil
            return
        }

        // Require a sustained charge before recording: regen while the wheel-speed reply
        // still reads 0 km/h, or BMS offset at a red light, used to open sub-minute
        // sessions. The start is backdated to the first observation.
        if pendingChargeStart == nil {
            pendingChargeStart = (now, telemetry.stateOfChargePct)
        }
        guard let pending = pendingChargeStart else { return }
        let confirmation = isDemoMode ? 0 : Self.startConfirmationSeconds
        guard now.timeIntervalSince(pending.time) >= confirmation else { return }

        nonChargingSnapshotCount = 0
        startSession(startSoc: pending.soc, startedAt: pending.time)
        pendingChargeStart = nil
        recordSnapshot(telemetry, chargingPower: chargingPower, displayedSoc: displayedSoc, at: now)
    }

    public func recordSnapshot(_ telemetry: TelemetrySnapshot, chargingPower: Double, displayedSoc: Double? = nil, at now: Date = .now) {
        guard let session = currentSession, session.endTime == nil else { return }
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
            liveEnergyKWh = session.totalKWhDelivered
        }

        if telemetry.stateOfChargePct > 0 {
            session.endSocPct = telemetry.stateOfChargePct
            checkChargeTarget(
                soc: displayedSoc ?? telemetry.stateOfChargePct,
                rawSoc: telemetry.stateOfChargePct,
                startSoc: session.startSocPct)
        }
        appendCurveSample(socPct: telemetry.stateOfChargePct, powerKW: chargingPower, at: now)
        if let lastSaveTime, now.timeIntervalSince(lastSaveTime) >= 30 {
            save()
            self.lastSaveTime = now
        }
    }

    /// Notifies once when the pack passes the driver's target, including when the session
    /// started above a lower target (nothing to announce) or demo mode is running.
    private func checkChargeTarget(soc: Double, rawSoc: Double, startSoc: Double) {
        guard !isDemoMode, !hasNotifiedChargeTarget, soc.isFinite else { return }
        let target = ChargingTarget.value()
        // Compare on the scale the dashboard shows: a saved SOC reference can display 85%
        // while the ECU reports 80%, and the alert used to announce the raw value. Shift
        // the stored raw start by the same offset so the start-above-target guard agrees.
        let offset = (soc - rawSoc).isFinite ? soc - rawSoc : 0
        guard startSoc + offset < target, soc >= target else { return }
        hasNotifiedChargeTarget = true
        #if os(iOS)
        NotificationService.shared.notifyChargeTargetReached(targetSOC: target, socPct: soc)
        #endif
    }

    /// Adds at most one point per percent of SOC or minute, whichever comes first, so a
    /// long session stores a readable curve without one row per poll cycle.
    private func appendCurveSample(socPct: Double, powerKW: Double, at date: Date) {
        guard let session = currentSession, session.endTime == nil, socPct.isFinite, socPct > 0 else { return }
        guard session.curveSamples.count < Self.maxCurveSamples else { return }
        if let last = lastCurveSample {
            let socChanged = abs(socPct - last.socPct) >= 1
            let timeElapsed = date.timeIntervalSince(last.timestamp) >= 60
            guard socChanged || timeElapsed else { return }
        }
        let sample = ChargingSampleModel(timestamp: date, socPct: socPct, powerKW: max(0, powerKW))
        session.samples?.append(sample)
        lastCurveSample = (date, socPct)
    }
}
