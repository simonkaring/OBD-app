import Foundation

/// The state of charge the driver wants to reach, shared by the charging screen, the
/// time-to-target estimate, and the target-reached notification.
public enum ChargingTarget {
    /// `@AppStorage` key read by the Charging tab and Settings.
    public static let socKey = "charging.targetSOC"
    public static let defaultSOC = 80.0
    /// Offered targets, in percent. Kept coarse so the picker stays a single screen.
    public static let options: [Double] = [50, 60, 70, 80, 90, 95, 100]

    /// The stored target, falling back to the default when the value is missing or invalid.
    public static func value(in defaults: UserDefaults = .standard) -> Double {
        guard let stored = defaults.object(forKey: socKey) as? Double, options.contains(stored) else {
            return defaultSOC
        }
        return stored
    }
}
