import Foundation

/// The most recent service distance a vehicle profile has reported.
public struct ServiceIntervalSnapshot: Equatable, Sendable {
    /// Kilometers remaining until the next service, as reported by the vehicle.
    public let remainingKm: Double
    public let observedAt: Date

    public init(remainingKm: Double, observedAt: Date) {
        self.remainingKm = remainingKm
        self.observedAt = observedAt
    }
}

/// Remembers the vehicle-reported distance to the next service and raises a local alert when
/// it gets close.
///
/// The metric itself is already decoded for the Mercedes EQA (OBDb) profile but never shown
/// anywhere, so this keeps the last value per vehicle and turns the threshold into a weekly
/// reminder instead of a number buried in a dashboard tile.
@MainActor
public struct ServiceReminderMonitor {
    public enum Key {
        public static let thresholdKm = "service.reminderThresholdKm"
        static let lastDistancePrefix = "service.lastDistance."
        static let lastObservedPrefix = "service.lastObserved."
        static let lastNotifiedPrefix = "service.lastNotified."
    }

    public static let defaultThresholdKm = 1000.0
    /// One reminder a week is enough; the flag is per vehicle so two cars do not share it.
    public static let reminderCooldown: TimeInterval = 7 * 86_400
    /// Thresholds offered in Settings, in kilometers.
    public static let options: [Double] = [500, 1000, 2000, 5000]
    /// Matches `TelemetryMetric.serviceDistance`'s plausibility bound.
    public static let plausibleRange = 0.0...65_535.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var thresholdKm: Double {
        guard let stored = defaults.object(forKey: Key.thresholdKm) as? Double, Self.options.contains(stored) else {
            return Self.defaultThresholdKm
        }
        return stored
    }

    public func snapshot(for vehicleName: String) -> ServiceIntervalSnapshot? {
        guard !vehicleName.isEmpty,
            let distance = defaults.object(forKey: Self.lastDistanceKey(vehicleName)) as? Double,
            let observedAt = defaults.object(forKey: Self.lastObservedKey(vehicleName)) as? Date
        else { return nil }
        return ServiceIntervalSnapshot(remainingKm: distance, observedAt: observedAt)
    }

    /// Stores the latest reading and notifies when it crosses the threshold.
    /// - Returns: the stored snapshot, or nil when the reading is implausible.
    @discardableResult
    public func observe(distanceKm: Double, vehicleName: String, at date: Date = .now) -> ServiceIntervalSnapshot? {
        guard distanceKm.isFinite, Self.plausibleRange.contains(distanceKm), !vehicleName.isEmpty else { return nil }

        // Telemetry arrives about once a second; only touch UserDefaults when the value
        // changed or the timestamp is getting old enough to be worth refreshing.
        let previous = snapshot(for: vehicleName)
        if previous?.remainingKm != distanceKm || previous.map({ date.timeIntervalSince($0.observedAt) >= 60 }) ?? true {
            defaults.set(distanceKm, forKey: Self.lastDistanceKey(vehicleName))
            defaults.set(date, forKey: Self.lastObservedKey(vehicleName))
        }

        #if os(iOS)
        let enabled = defaults.object(forKey: NotificationService.PreferenceKey.serviceDue) as? Bool ?? true
        let lastNotified = defaults.object(forKey: Self.lastNotifiedKey(vehicleName)) as? Date
        if Self.shouldRemind(
            remainingKm: distanceKm, thresholdKm: thresholdKm, lastNotifiedAt: lastNotified, enabled: enabled, at: date)
        {
            defaults.set(date, forKey: Self.lastNotifiedKey(vehicleName))
            NotificationService.shared.notifyServiceDue(remainingKm: distanceKm)
        }
        #endif

        return ServiceIntervalSnapshot(remainingKm: distanceKm, observedAt: date)
    }

    /// Pure decision used by `observe` (and tested without a notification center).
    public static func shouldRemind(
        remainingKm: Double,
        thresholdKm: Double,
        lastNotifiedAt: Date?,
        enabled: Bool,
        at date: Date
    ) -> Bool {
        guard enabled, remainingKm.isFinite, thresholdKm.isFinite, thresholdKm > 0, remainingKm <= thresholdKm else {
            return false
        }
        guard let lastNotifiedAt else { return true }
        return date.timeIntervalSince(lastNotifiedAt) >= reminderCooldown
    }

    private static func lastDistanceKey(_ vehicleName: String) -> String {
        Key.lastDistancePrefix + vehicleName
    }

    private static func lastObservedKey(_ vehicleName: String) -> String {
        Key.lastObservedPrefix + vehicleName
    }

    private static func lastNotifiedKey(_ vehicleName: String) -> String {
        Key.lastNotifiedPrefix + vehicleName
    }
}
