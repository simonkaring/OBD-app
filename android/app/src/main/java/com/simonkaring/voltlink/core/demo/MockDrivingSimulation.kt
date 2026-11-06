package com.simonkaring.voltlink.core.demo

import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.sin

enum class DemoScenario(val label: String) {
    CITY_DRIVING("City Drive (Regen & Stop-and-Go)"),
    HIGHWAY_CRUISING("Highway Fast Cruise (120 km/h)"),
    DC_FAST_CHARGING("DC Fast Charging (100 kW Tapering)"),
    FAULT_INJECTION("Diagnostic Fault Injection"),
}

/**
 * Physics-ish driving simulation behind Demo Mode. Port of the iOS
 * `MockDrivingSimulation`: a 5 Hz tick produces a full telemetry snapshot, and manual
 * speed/throttle/regen overrides are honoured by the city cycle.
 */
class MockDrivingSimulation(private val scope: CoroutineScope) {
    private val _scenario = MutableStateFlow(DemoScenario.CITY_DRIVING)
    var scenario: DemoScenario
        get() = _scenario.value
        set(value) {
            _scenario.value = value
            if (value == DemoScenario.FAULT_INJECTION) _injectedFaultCode.value = "P0A80"
        }

    var userSpeedOverride: Double? = null
    var userThrottleOverride: Double? = null
    var userRegenOverride: Double? = null

    private val _injectedFaultCode = MutableStateFlow<String?>(null)
    val injectedFaultCode: StateFlow<String?> = _injectedFaultCode.asStateFlow()

    private val _telemetry = MutableStateFlow(
        TelemetrySnapshot(
            stateOfChargePct = 78.5,
            stateOfHealthPct = 98.2,
            voltageV = 368.4,
            aux12VVolts = 13.8,
            batteryTempC = 26.5,
            fuelLevelPct = 62.0,
            coolantTempC = 88.0,
            intakeAirTempC = 24.0,
        ),
    )
    val telemetry: StateFlow<TelemetrySnapshot> = _telemetry.asStateFlow()

    private var job: Job? = null
    private var simulationStep = 0.0

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch(Dispatchers.Default) {
            while (isActive) {
                stepSimulation()
                delay(200)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    fun clearInjectedFault() {
        _injectedFaultCode.value = null
        if (scenario == DemoScenario.FAULT_INJECTION) scenario = DemoScenario.CITY_DRIVING
    }

    private fun stepSimulation() {
        simulationStep += 0.2
        var next = _telemetry.value.copy(timestamp = java.time.Instant.now())

        when (scenario) {
            DemoScenario.CITY_DRIVING -> next = simulateCityDriving(next)
            DemoScenario.HIGHWAY_CRUISING -> next = simulateHighwayDriving(next)
            DemoScenario.DC_FAST_CHARGING -> next = simulateDcFastCharging(next)
            DemoScenario.FAULT_INJECTION -> {
                next = simulateCityDriving(next)
                _injectedFaultCode.value = "P0A80"
            }
        }

        next = stepGenericDerivedMetrics(next)
        val now = next.timestamp
        next = next.copy(
            speedUpdatedAt = now,
            powerUpdatedAt = now,
            voltageUpdatedAt = now,
            currentUpdatedAt = now,
            vehicleRangeKm = 426 * next.stateOfChargePct / 100,
            vehicleRangeUpdatedAt = now,
            sohUpdatedAt = now,
            batteryTempUpdatedAt = now,
            coolantTempUpdatedAt = now,
            intakeAirTempUpdatedAt = now,
        )
        _telemetry.value = next
    }

    /** Derives the generic SAE J1979 fields from the same physics state. */
    private fun stepGenericDerivedMetrics(telemetry: TelemetrySnapshot): TelemetrySnapshot {
        val throttle = userThrottleOverride ?: (telemetry.powerKW / 85.0).coerceIn(0.0, 1.0)
        val targetCoolant = 82.0 + minOf(20.0, telemetry.powerKW * 0.15)
        var fuel = telemetry.fuelLevelPct
        if (telemetry.powerKW > 0) fuel = maxOf(0.0, fuel - telemetry.powerKW * 0.0006)
        return telemetry.copy(
            throttlePositionPct = throttle * 100.0,
            engineLoadPct = (telemetry.powerKW / 140.0 * 100.0).coerceIn(0.0, 100.0),
            coolantTempC = telemetry.coolantTempC + (targetCoolant - telemetry.coolantTempC) * 0.02,
            intakeAirTempC = 24.0 + sin(simulationStep * 0.05) * 2.0,
            fuelLevelPct = fuel,
        )
    }

    private fun simulateCityDriving(telemetry: TelemetrySnapshot): TelemetrySnapshot {
        val targetSpeed = userSpeedOverride ?: maxOf(0.0, sin(simulationStep * 0.15) * 65.0)
        val speedDelta = targetSpeed - telemetry.speedKmH
        val speed = telemetry.speedKmH + speedDelta * 0.1

        val power: Double
        val current: Double
        when {
            speedDelta > 0.5 -> {
                val throttle = userThrottleOverride ?: (speedDelta / 5.0)
                power = minOf(140.0, maxOf(5.0, throttle * 85.0))
                current = power * 1000.0 / telemetry.voltageV
            }
            speedDelta < -0.5 -> {
                val regen = userRegenOverride ?: 0.6
                power = maxOf(-48.0, -1.0 * regen * 45.0)
                current = power * 1000.0 / telemetry.voltageV
            }
            else -> {
                power = 2.5
                current = 6.8
            }
        }

        val energyDeltaKWh = power * (0.2 / 3600.0)
        val soc = (telemetry.stateOfChargePct - (energyDeltaKWh / 66.5) * 100.0).coerceIn(5.0, 100.0)
        return telemetry.copy(
            isCharging = false,
            chargePowerKW = 0.0,
            speedKmH = speed,
            powerKW = power,
            currentA = current,
            stateOfChargePct = soc,
            motorRpm = speed * 95.0,
            motorTorqueNm = power * 3.2,
            batteryTempC = 25.0 + power * 0.03,
            voltageV = 370.0 - power * 0.15,
        )
    }

    private fun simulateHighwayDriving(telemetry: TelemetrySnapshot): TelemetrySnapshot {
        val speed = (userSpeedOverride ?: 122.0) + sin(simulationStep * 0.5) * 2.0
        val power = 26.5 + sin(simulationStep * 0.3) * 4.0
        val energyDeltaKWh = power * (0.2 / 3600.0)
        return telemetry.copy(
            isCharging = false,
            chargePowerKW = 0.0,
            speedKmH = speed,
            powerKW = power,
            currentA = power * 1000.0 / 362.0,
            voltageV = 362.0,
            stateOfChargePct = maxOf(5.0, telemetry.stateOfChargePct - (energyDeltaKWh / 66.5) * 100.0),
            batteryTempC = minOf(42.0, 31.0 + simulationStep * 0.02),
            motorRpm = speed * 95.0,
            motorTorqueNm = 185.0,
        )
    }

    private fun simulateDcFastCharging(telemetry: TelemetrySnapshot): TelemetrySnapshot {
        val soc = telemetry.stateOfChargePct
        val peakKW = when {
            soc < 55.0 -> 100.0
            soc < 75.0 -> 100.0 - ((soc - 55.0) / 20.0) * 30.0
            soc < 85.0 -> 70.0 - ((soc - 75.0) / 10.0) * 25.0
            else -> maxOf(12.0, 45.0 - ((soc - 85.0) / 15.0) * 33.0)
        }
        val voltage = 370.0 + soc * 0.4
        val chargedKWh = peakKW * (0.2 / 3600.0) * 15.0 // 15x accelerated simulation
        return telemetry.copy(
            speedKmH = 0.0,
            powerKW = 0.0,
            motorRpm = 0.0,
            motorTorqueNm = 0.0,
            isCharging = true,
            chargePowerKW = peakKW,
            chargePowerSource = com.simonkaring.voltlink.core.telemetry.ChargePowerSource.MEASURED,
            chargePowerUpdatedAt = telemetry.timestamp,
            voltageV = voltage,
            currentA = -1.0 * (peakKW * 1000.0) / voltage,
            stateOfChargePct = minOf(100.0, soc + (chargedKWh / 66.5) * 100.0),
            batteryTempC = minOf(45.0, 28.0 + soc * 0.15),
        )
    }
}
