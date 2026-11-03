import Foundation

/// A charge-power reading placed on the state-of-charge axis, used to project how long the
/// rest of a session will take.
public struct ChargingCurveSample: Sendable, Equatable {
    public let socPct: Double
    public let powerKW: Double

    public init(socPct: Double, powerKW: Double) {
        self.socPct = socPct
        self.powerKW = powerKW
    }
}

/// Projects remaining charging time by integrating energy band-by-band instead of dividing
/// once by the current rate.
///
/// A single division by the live power is badly wrong on DC chargers because the pack tapers
/// as it fills: an 80 kW session shows a 10-minute estimate for the last 10% that in reality
/// takes 40. The estimator walks 1% SOC bands, projects the power in each band from the
/// session's own curve, and sums the energy needed. AC charging does not taper, so it keeps
/// the current rate. Everything here is a deterministic function of its inputs so the
/// arithmetic is unit-tested without a live session.
public enum ChargingTimeEstimator {
    /// Above this rate the session is assumed to be DC, where the pack tapers toward full.
    public static let dcPowerThresholdKW = 22.0
    /// State of charge where a DC session starts tapering in the fallback model.
    public static let taperStartSOC = 80.0
    /// Fraction of the current rate still delivered near 100% in the fallback model.
    public static let taperFloorRatio = 0.2
    /// How fast the fallback taper decays: after this many percentage points past
    /// `taperStartSOC`, the rate has fallen by roughly 63% of the way to its floor.
    public static let taperDecaySOC = 6.0
    /// Refuse to show an estimate beyond this horizon; it means the inputs are implausible.
    public static let maximumEstimate: TimeInterval = 24 * 3600

    /// Seconds needed to charge from `currentSOC` to `targetSOC`.
    ///
    /// - Parameters:
    ///   - observedCurve: Power/SOC readings from the current session. When they show the
    ///     rate falling, their slope projects the next bands; otherwise the DC taper model is
    ///     used above 80%.
    /// - Returns: `0` when the target is already reached, and `nil` for unusable inputs.
    public static func secondsToTarget(
        currentSOC: Double,
        targetSOC: Double,
        currentPowerKW: Double,
        capacityKWh: Double,
        observedCurve: [ChargingCurveSample] = []
    ) -> TimeInterval? {
        guard currentSOC.isFinite, targetSOC.isFinite, currentPowerKW.isFinite, capacityKWh.isFinite else { return nil }
        guard (0...100).contains(currentSOC), (0...100).contains(targetSOC) else { return nil }
        guard capacityKWh > 0, currentPowerKW > 0.5 else { return nil }
        guard targetSOC > currentSOC else { return 0 }

        var seconds: TimeInterval = 0
        var soc = currentSOC
        while soc < targetSOC - 0.0001 {
            let bandEnd = min(targetSOC, soc + 1.0)
            let power = projectedPowerKW(
                atSOC: (soc + bandEnd) / 2,
                currentSOC: currentSOC,
                currentPowerKW: currentPowerKW,
                observedCurve: observedCurve)
            guard power > 0.05, power.isFinite else { return nil }
            let energyKWh = capacityKWh * (bandEnd - soc) / 100.0
            seconds += energyKWh / power * 3600.0
            guard seconds.isFinite, seconds <= maximumEstimate else { return nil }
            soc = bandEnd
        }
        return seconds
    }

    /// Charge rate expected at a future state of charge.
    ///
    /// AC sessions hold their rate. DC sessions either continue the slope the session has
    /// already shown, or, when the curve is too short to fit one, follow a linear taper from
    /// 80% to `taperFloorRatio` of the current rate at 100%.
    public static func projectedPowerKW(
        atSOC soc: Double,
        currentSOC: Double,
        currentPowerKW: Double,
        observedCurve: [ChargingCurveSample]
    ) -> Double {
        guard soc > currentSOC, currentPowerKW > dcPowerThresholdKW else { return currentPowerKW }

        if let slope = observedTaperSlope(curve: observedCurve) {
            let projected = currentPowerKW + slope * (soc - currentSOC)
            let floor = max(0.5, currentPowerKW * 0.05)
            return min(currentPowerKW, max(floor, projected))
        }

        // Real DC curves fall away quickly after 80% rather than in a straight line, so a
        // linear taper over 80...100 systematically overestimates the last 20 points.
        guard soc > taperStartSOC else { return currentPowerKW }
        let ratio = taperFloorRatio + (1.0 - taperFloorRatio) * exp(-(soc - taperStartSOC) / taperDecaySOC)
        return currentPowerKW * ratio
    }

    /// Negative kW-per-percent slope from the newest part of the curve, if it is measurable.
    ///
    /// Uses the last two readings at least half a percent apart so SOC jitter between polls
    /// does not produce an absurd slope. A curve that is flat or rising yields nil, and the
    /// fallback taper applies instead.
    static func observedTaperSlope(curve: [ChargingCurveSample]) -> Double? {
        let readings =
            curve
            .filter { $0.socPct.isFinite && $0.powerKW.isFinite && $0.socPct > 0 && $0.powerKW > 0 }
            .sorted { $0.socPct < $1.socPct }
        guard let last = readings.last else { return nil }

        let previous = readings.last { last.socPct - $0.socPct >= 0.5 }
        guard let previous, last.socPct > previous.socPct else { return nil }
        let slope = (last.powerKW - previous.powerKW) / (last.socPct - previous.socPct)
        return slope < 0 && slope.isFinite ? slope : nil
    }
}
