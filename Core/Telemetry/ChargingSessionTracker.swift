import Foundation

public struct ChargingDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let powerKW: Double
    public let soc: Double
    public let packVoltage: Double
    public let packCurrent: Double

    public init(timestamp: Date = Date(), powerKW: Double, soc: Double, packVoltage: Double, packCurrent: Double) {
        self.timestamp = timestamp
        self.powerKW = powerKW
        self.soc = soc
        self.packVoltage = packVoltage
        self.packCurrent = packCurrent
    }
}

public struct ChargingSessionState: Sendable {
    public var isCharging: Bool = false
    public var startTime: Date?
    public var startSOC: Double?
    public var currentSOC: Double?
    public var currentPowerKW: Double = 0.0
    public var peakPowerKW: Double = 0.0
    public var totalEnergyKWh: Double = 0.0
    public var history: [ChargingDataPoint] = []
    
    public var sessionDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    public var socGained: Double {
        guard let start = startSOC, let current = currentSOC else { return 0.0 }
        return max(0.0, current - start)
    }

    public init() {}
}

public final class ChargingSessionTracker: @unchecked Sendable {
    public private(set) var state = ChargingSessionState()
    private var lastUpdateTimestamp: Date?

    public init() {}

    public func reset() {
        state = ChargingSessionState()
        lastUpdateTimestamp = nil
    }

    /// Process a new telemetry update and compute live charging metrics
    public func update(
        soc: Double?,
        packVoltage: Double?,
        packCurrent: Double?,
        powerKW: Double?,
        vehicleBatteryCapacityKWh: Double,
        isStationary: Bool
    ) -> ChargingSessionState {
        let now = Date()
        
        let livePowerKW: Double
        if let p = powerKW {
            livePowerKW = p
        } else if let v = packVoltage, let i = packCurrent {
            livePowerKW = (v * abs(i)) / 1000.0
        } else {
            livePowerKW = 0.0
        }

        // Active charging criteria: Vehicle is stationary and receiving power (> 0.5 kW)
        let isActivelyCharging = isStationary && (livePowerKW > 0.5 || (packCurrent != nil && (packCurrent! < -0.5 || (packCurrent! > 0.5 && isStationary))))

        if isActivelyCharging {
            if !state.isCharging {
                // Session Start
                state.isCharging = true
                state.startTime = now
                state.startSOC = soc
                state.peakPowerKW = livePowerKW
                state.totalEnergyKWh = 0.0
                state.history.removeAll()
            }

            // Integrate kWh over dt
            if let lastTime = lastUpdateTimestamp {
                let dtHours = now.timeIntervalSince(lastTime) / 3600.0
                if dtHours > 0 && dtHours < (5.0 / 60.0) { // Discard abnormal gaps > 5 mins
                    state.totalEnergyKWh += livePowerKW * dtHours
                }
            }

            state.currentPowerKW = livePowerKW
            if livePowerKW > state.peakPowerKW {
                state.peakPowerKW = livePowerKW
            }

            if let currentSOC = soc {
                state.currentSOC = currentSOC
                if state.startSOC == nil {
                    state.startSOC = currentSOC
                }
            }

            // Append curve data point at ~2 second resolution
            if state.history.isEmpty || now.timeIntervalSince(state.history.last!.timestamp) >= 2.0 {
                let point = ChargingDataPoint(
                    timestamp: now,
                    powerKW: livePowerKW,
                    soc: soc ?? state.currentSOC ?? 0.0,
                    packVoltage: packVoltage ?? 0.0,
                    packCurrent: packCurrent ?? 0.0
                )
                state.history.append(point)
            }
        } else {
            if state.isCharging {
                // Session Ended
                state.isCharging = false
            }
            state.currentPowerKW = 0.0
        }

        lastUpdateTimestamp = now
        return state
    }

    /// Estimates time (in seconds) to reach target SoC based on battery capacity and current charging power
    public func estimatedSecondsToTarget(targetSOC: Double, batteryCapacityKWh: Double) -> TimeInterval? {
        guard state.isCharging,
              let currentSOC = state.currentSOC,
              currentSOC < targetSOC,
              state.currentPowerKW > 0.5,
              batteryCapacityKWh > 0 else {
            return nil
        }

        let neededPercentage = (targetSOC - currentSOC) / 100.0
        let neededKWh = batteryCapacityKWh * neededPercentage
        
        let effectivePowerKW: Double
        if targetSOC > 80.0 && currentSOC >= 80.0 {
            effectivePowerKW = max(1.0, state.currentPowerKW * 0.5)
        } else {
            effectivePowerKW = state.currentPowerKW
        }

        let hours = neededKWh / effectivePowerKW
        return hours * 3600.0
    }
}
