import Foundation
import UserNotifications

/// Local notifications for events the user cares about while VoltLink is in the
/// background. All events are opt-out via Settings and never contain raw vehicle data.
@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    /// UserDefaults keys are public so the Settings toggles bind to the same flags.
    public enum PreferenceKey {
        public static let chargingFinished = "notifications.chargingFinished"
        public static let adapterDisconnected = "notifications.adapterDisconnected"
        public static let faultCodes = "notifications.faultCodes"
    }

    private let defaults: UserDefaults
    private var lastAdapterLostNotification: Date?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(_ key: String) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? true
    }

    /// Requests permission the first time any notification toggle is enabled.
    public func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func notifyChargingFinished(endSocPct: Double) {
        guard isEnabled(PreferenceKey.chargingFinished) else { return }
        post(
            title: "Charging Finished",
            body: "The charging session ended at \(Int(endSocPct.rounded()))% state of charge.",
            identifier: "charging-finished"
        )
    }

    public func notifyAdapterDisconnected() {
        guard isEnabled(PreferenceKey.adapterDisconnected) else { return }
        // A flapping adapter must not produce a notification storm.
        if let lastAdapterLostNotification, Date().timeIntervalSince(lastAdapterLostNotification) < 300 { return }
        lastAdapterLostNotification = Date()
        post(
            title: "OBD Adapter Disconnected",
            body: "The trip is still being recorded, but live telemetry has stopped. Reconnect the adapter to resume.",
            identifier: "adapter-disconnected"
        )
    }

    public func notifyFaultCodes(count: Int) {
        guard isEnabled(PreferenceKey.faultCodes), count > 0 else { return }
        post(
            title: "\(count) Fault Code\(count == 1 ? "" : "s") Found",
            body: "Open VoltLink's Diagnostics tab to review the stored and pending codes.",
            identifier: "fault-codes"
        )
    }

    private func post(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(identifier)-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
