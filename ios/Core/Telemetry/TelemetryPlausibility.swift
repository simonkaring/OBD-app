import Foundation

/// Physically plausible bounds per decoded quantity. Several vehicle profiles carry
/// unverified community scaling factors; rejecting out-of-range values here means a
/// wrong decode shows up as *missing* data on the dashboard rather than as garbage.
public enum TelemetryPlausibility {
    public static func isPlausible(_ update: TelemetryUpdate) -> Bool {
        func ok(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
            value.isFinite && range.contains(value)
        }

        switch update {
        case .speed(let v): return ok(v, 0...400)
        case .power(let volts, let amps, let kw):
            return ok(volts, 0...1_000) && ok(amps, -1_500...1_500) && ok(kw, -1_000...1_000)
        case .packVoltage(let v): return ok(v, 0...1_000)
        case .packCurrent(let v): return ok(v, -1_500...1_500)
        case .soc(let v): return ok(v, 0...100)
        case .soh(let v): return ok(v, 0...100)
        case .batteryTemp(let lo, let hi, let avg):
            return ok(lo, -50...100) && ok(hi, -50...100) && ok(avg, -50...100)
        case .aux12V(let v): return ok(v, 0...36)
        case .motorStats(let rpm, let torque): return ok(rpm, -30_000...30_000) && ok(torque, -5_000...5_000)
        case .hvacPower(let v): return ok(v, -50...50)
        case .chargingStats(let kw, _): return kw.map { ok($0, 0...600) } ?? true
        case .fuelLevel(let v): return ok(v, 0...100)
        case .throttlePosition(let v): return ok(v, 0...100)
        case .engineLoad(let v): return ok(v, 0...100)
        case .coolantTemp(let v): return ok(v, -50...250)
        case .intakeAirTemp(let v): return ok(v, -50...200)
        case .ambientAirTemp(let v): return ok(v, -60...80)
        case .maf(let v): return ok(v, 0...700)
        case .manifoldPressure(let v): return ok(v, 0...500)
        case .oilTemp(let v): return ok(v, -50...250)
        case .timingAdvance(let v): return ok(v, -70...70)
        case .barometricPressure(let v): return ok(v, 0...300)
        case .vehicleRange(let v): return ok(v, 0...1_000)
        case .communityMetric(let metric, let value):
            switch metric {
            case .frontLeftWheelSpeed, .frontRightWheelSpeed, .rearLeftWheelSpeed, .rearRightWheelSpeed: return ok(value, 0...400)
            case .longitudinalAcceleration, .lateralAcceleration, .yawRate: return ok(value, -10...10)
            case .steeringAngle: return ok(value, -3_600...3_600)
            case .brakeCylinderPressure, .vacuumBrakePressure: return ok(value, -500...500)
            case .aux12VHighDefinition, .converterRequestedVoltage: return ok(value, 0...36)
            case .serviceDistance: return ok(value, 0...65_535)
            default: return false
            }
        case .genericPid: return true
        }
    }
}
