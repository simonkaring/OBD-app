import Foundation
import Combine

public enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case cityDriving = "City Drive (Regen & Stop-and-Go)"
    case highwayCruising = "Highway Fast Cruise (120 km/h)"
    case dcFastCharging = "DC Fast Charging (100 kW Tapering)"
    case faultInjection = "Diagnostic Fault Injection"

    public var id: String { rawValue }
}

public final class MockDrivingSimulation: ObservableObject {
    @Published public var scenario: DemoScenario = .cityDriving
    @Published public var userSpeedOverride: Double? = nil
    @Published public var userThrottleOverride: Double? = nil
    @Published public var userRegenOverride: Double? = nil
    @Published public var injectedFaultCode: String? = nil

    @Published public private(set) var telemetry = TelemetrySnapshot()

    private var timer: AnyCancellable?
    private var simulationStep: Double = 0.0

    public init() {
        telemetry.stateOfChargePct = 78.5
        telemetry.stateOfHealthPct = 98.2
        telemetry.voltageV = 368.4
        telemetry.aux12VVolts = 13.8
        telemetry.batteryTempC = 26.5
        telemetry.fuelLevelPct = 62.0
        telemetry.coolantTempC = 88.0
        telemetry.intakeAirTempC = 24.0
    }

    public func start() {
        stop()
        timer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.stepSimulation()
            }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    func stepSimulation() {
        simulationStep += 0.2
        var nextTelemetry = telemetry
        nextTelemetry.timestamp = .now

        switch scenario {
        case .cityDriving:
            simulateCityDriving(&nextTelemetry)
        case .highwayCruising:
            simulateHighwayDriving(&nextTelemetry)
        case .dcFastCharging:
            simulateDCFastCharging(&nextTelemetry)
        case .faultInjection:
            simulateFaultScenario(&nextTelemetry)
        }

        stepGenericDerivedMetrics(&nextTelemetry)
        nextTelemetry.speedUpdatedAt = nextTelemetry.timestamp
        nextTelemetry.powerUpdatedAt = nextTelemetry.timestamp
        nextTelemetry.voltageUpdatedAt = nextTelemetry.timestamp
        nextTelemetry.currentUpdatedAt = nextTelemetry.timestamp
        nextTelemetry.vehicleRangeKm = 426 * nextTelemetry.stateOfChargePct / 100
        nextTelemetry.vehicleRangeUpdatedAt = nextTelemetry.timestamp
        telemetry = nextTelemetry
    }

    /// Derives the "any car" (non-EV, SAE J1979) fields from the same physics state
    /// used above, so switching to `GenericOBD2Profile` in Demo Mode isn't flatlined at zero.
    private func stepGenericDerivedMetrics(_ telemetry: inout TelemetrySnapshot) {
        let throttle = userThrottleOverride ?? max(0.0, min(1.0, telemetry.powerKW / 85.0))
        telemetry.throttlePositionPct = throttle * 100.0
        telemetry.engineLoadPct = max(0.0, min(100.0, (telemetry.powerKW / 140.0) * 100.0))

        let targetCoolant = 82.0 + min(20.0, telemetry.powerKW * 0.15)
        telemetry.coolantTempC += (targetCoolant - telemetry.coolantTempC) * 0.02
        telemetry.intakeAirTempC = 24.0 + sin(simulationStep * 0.05) * 2.0

        if telemetry.powerKW > 0 {
            let fuelDelta = (telemetry.powerKW * 0.0006)
            telemetry.fuelLevelPct = max(0.0, telemetry.fuelLevelPct - fuelDelta)
        }
    }

    private func simulateCityDriving(_ telemetry: inout TelemetrySnapshot) {
        telemetry.isCharging = false
        telemetry.chargePowerKW = 0.0

        let targetSpeed: Double
        if let manualSpeed = userSpeedOverride {
            targetSpeed = manualSpeed
        } else {
            // Oscillate speed 0 -> 65 km/h
            let phase = sin(simulationStep * 0.15)
            targetSpeed = max(0.0, phase * 65.0)
        }

        let speedDelta = targetSpeed - telemetry.speedKmH
        telemetry.speedKmH += speedDelta * 0.1

        if speedDelta > 0.5 {
            // Acceleration -> draw positive kW
            let throttle = userThrottleOverride ?? (speedDelta / 5.0)
            telemetry.powerKW = min(140.0, max(5.0, throttle * 85.0))
            telemetry.currentA = (telemetry.powerKW * 1000.0) / telemetry.voltageV
        } else if speedDelta < -0.5 {
            // Braking -> negative kW (Regen)
            let regen = userRegenOverride ?? 0.6
            telemetry.powerKW = max(-48.0, -1.0 * regen * 45.0)
            telemetry.currentA = (telemetry.powerKW * 1000.0) / telemetry.voltageV
        } else {
            // Coasting
            telemetry.powerKW = 2.5
            telemetry.currentA = 6.8
        }

        // Drain SOC slowly based on power
        let energyDeltaKWh = (telemetry.powerKW * (0.2 / 3600.0))
        let socDelta = (energyDeltaKWh / 66.5) * 100.0
        telemetry.stateOfChargePct = max(5.0, min(100.0, telemetry.stateOfChargePct - socDelta))

        telemetry.motorRpm = telemetry.speedKmH * 95.0
        telemetry.motorTorqueNm = telemetry.powerKW * 3.2
        telemetry.batteryTempC = 25.0 + (telemetry.powerKW * 0.03)
        telemetry.voltageV = 370.0 - (telemetry.powerKW * 0.15)
    }

    private func simulateHighwayDriving(_ telemetry: inout TelemetrySnapshot) {
        telemetry.isCharging = false
        telemetry.chargePowerKW = 0.0

        let baseSpeed = userSpeedOverride ?? 122.0
        let speedNoise = sin(simulationStep * 0.5) * 2.0
        telemetry.speedKmH = baseSpeed + speedNoise

        // High steady consumption ~22 kWh/100km -> ~27 kW power draw
        telemetry.powerKW = 26.5 + sin(simulationStep * 0.3) * 4.0
        telemetry.currentA = (telemetry.powerKW * 1000.0) / 362.0
        telemetry.voltageV = 362.0

        let energyDeltaKWh = (telemetry.powerKW * (0.2 / 3600.0))
        telemetry.stateOfChargePct = max(5.0, telemetry.stateOfChargePct - ((energyDeltaKWh / 66.5) * 100.0))
        telemetry.batteryTempC = min(42.0, 31.0 + (simulationStep * 0.02))
        telemetry.motorRpm = telemetry.speedKmH * 95.0
        telemetry.motorTorqueNm = 185.0
    }

    private func simulateDCFastCharging(_ telemetry: inout TelemetrySnapshot) {
        telemetry.speedKmH = 0.0
        telemetry.powerKW = 0.0
        telemetry.motorRpm = 0.0
        telemetry.motorTorqueNm = 0.0
        telemetry.isCharging = true

        let soc = telemetry.stateOfChargePct
        // Mercedes EQA 250 DC 100 kW Charging Curve
        let peakKW: Double
        if soc < 55.0 {
            peakKW = 100.0
        } else if soc < 75.0 {
            peakKW = 100.0 - ((soc - 55.0) / 20.0) * 30.0 // 100 kW -> 70 kW
        } else if soc < 85.0 {
            peakKW = 70.0 - ((soc - 75.0) / 10.0) * 25.0  // 70 kW -> 45 kW
        } else {
            peakKW = max(12.0, 45.0 - ((soc - 85.0) / 15.0) * 33.0) // 45 kW -> 12 kW
        }

        telemetry.chargePowerKW = peakKW
        telemetry.voltageV = 370.0 + (soc * 0.4) // Voltage rises as battery fills
        telemetry.currentA = -1.0 * (peakKW * 1000.0) / telemetry.voltageV

        // Fast charge increases SOC rapidly in simulation
        let chargedKWh = (peakKW * (0.2 / 3600.0)) * 15.0 // Accelerated simulation 15x
        telemetry.stateOfChargePct = min(100.0, telemetry.stateOfChargePct + ((chargedKWh / 66.5) * 100.0))
        telemetry.batteryTempC = min(45.0, 28.0 + (soc * 0.15))
    }

    private func simulateFaultScenario(_ telemetry: inout TelemetrySnapshot) {
        simulateCityDriving(&telemetry)
        injectedFaultCode = "P0A80"
    }
}
