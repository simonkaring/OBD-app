import Foundation

/// Estimates charging power from the SoC slope when the vehicle/profile cannot report
/// pack current or an explicit charge rate. Kept as a value type so the history window
/// and invalidation rules are testable without a live adapter.
struct ChargingPowerEstimator {
    private var history: [(timestamp: Date, value: Double)] = []

    mutating func reset() {
        history.removeAll()
    }

    /// Clears an estimate that has outlived its SoC reading (or that must yield to a
    /// measured pack-power reading).
    mutating func clear(snapshot: inout TelemetrySnapshot) {
        guard snapshot.chargePowerSource == .socEstimate else { return }
        snapshot.isCharging = false
        snapshot.chargePowerKW = 0
        snapshot.chargePowerUpdatedAt = nil
        snapshot.chargePowerSource = nil
    }

    /// Drops the history window and the published estimate. Returns whether the snapshot
    /// changed so callers can decide whether to notify downstream consumers.
    @discardableResult
    mutating func invalidate(snapshot: inout TelemetrySnapshot) -> Bool {
        guard snapshot.chargePowerSource == .socEstimate else { return false }
        clear(snapshot: &snapshot)
        reset()
        return true
    }

    mutating func update(
        soc: Double,
        capacityKWh: Double,
        timestamp: Date,
        chargingPermitted: Bool,
        snapshot: inout TelemetrySnapshot
    ) {
        // A profile that reports pack current has better information than an SoC slope.
        // Keep its reading until it is stale.
        if snapshot.chargePowerSource == .measured,
            let directPowerAt = snapshot.chargePowerUpdatedAt,
            timestamp.timeIntervalSince(directPowerAt) < 10
        {
            return
        }

        guard capacityKWh.isFinite, capacityKWh > 0, chargingPermitted else {
            reset()
            clear(snapshot: &snapshot)
            return
        }

        history.append((timestamp, soc))
        let cutoff = timestamp.addingTimeInterval(-90)
        history.removeAll { $0.timestamp < cutoff }

        guard let oldest = history.first else { return }
        let duration = timestamp.timeIntervalSince(oldest.timestamp)
        let delta = soc - oldest.value
        guard duration >= 30 else { return }
        guard delta > 0 else {
            clear(snapshot: &snapshot)
            return
        }

        let kw = (delta / 100 * capacityKWh) / (duration / 3_600)
        guard (0.5...200).contains(kw) else {
            clear(snapshot: &snapshot)
            return
        }
        snapshot.isCharging = true
        snapshot.chargePowerKW = kw
        snapshot.chargePowerUpdatedAt = timestamp
        snapshot.chargePowerSource = .socEstimate
    }
}
