import Foundation

/// Elapsed-time and average-speed readouts shared by the Charging tab and the Charging log.
public enum ChargingSessionSummary {
    /// Compact duration label: `"<1m"`, `"8m"`, `"1h 05m"`.
    public static func duration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 60 else { return "<1m" }
        let minutes = Int(interval / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h " + String(format: "%02d", minutes % 60) + "m"
    }

    /// Mean charge power over a session — the same ratio `ChargingTrackingManager.stopSession`
    /// persists in `ChargingSessionModel.averagePowerKW`. `nil` until energy and time are known.
    public static func averagePowerKW(energyKWh: Double, over interval: TimeInterval) -> Double? {
        guard energyKWh.isFinite, energyKWh > 0, interval.isFinite, interval > 0 else { return nil }
        let average = energyKWh / (interval / 3600)
        return average.isFinite ? average : nil
    }
}
