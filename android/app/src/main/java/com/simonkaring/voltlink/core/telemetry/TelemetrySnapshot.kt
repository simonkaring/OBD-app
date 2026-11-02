package com.simonkaring.voltlink.core.telemetry

import java.time.Instant

/** Where a charge-power reading came from: measured pack current, or an inferred SoC slope. */
enum class ChargePowerSource { MEASURED, SOC_ESTIMATE }

/**
 * One coherent set of decoded vehicle values. Field defaults and freshness rules mirror the
 * iOS `TelemetrySnapshot` so both apps behave identically when a PID stops answering.
 */
data class TelemetrySnapshot(
    val timestamp: Instant = Instant.now(),
    val speedKmH: Double = 0.0,
    val speedUpdatedAt: Instant? = null,
    val powerKW: Double = 0.0,
    val powerUpdatedAt: Instant? = null,
    val voltageV: Double = 0.0,
    val voltageUpdatedAt: Instant? = null,
    val currentA: Double = 0.0,
    val currentUpdatedAt: Instant? = null,
    val vehicleRangeKm: Double? = null,
    val vehicleRangeUpdatedAt: Instant? = null,
    val communityValues: Map<TelemetryMetric, Double>? = null,
    /** Presentation-only value supplied by the active trip tracker. */
    val tripAverageConsumption: Double? = null,
    val stateOfChargePct: Double = 0.0,
    val socUpdatedAt: Instant? = null,
    val stateOfHealthPct: Double = 0.0,
    val batteryTempC: Double = 0.0,
    val batteryTempMinC: Double = 0.0,
    val batteryTempMaxC: Double = 0.0,
    val aux12VVolts: Double = 0.0,
    val motorRpm: Double = 0.0,
    val motorTorqueNm: Double = 0.0,
    val hvacPowerKW: Double = 0.0,
    val isCharging: Boolean = false,
    val chargePowerKW: Double = 0.0,
    val chargePowerUpdatedAt: Instant? = null,
    val chargePowerSource: ChargePowerSource? = null,
    val fuelLevelPct: Double = 0.0,
    val throttlePositionPct: Double = 0.0,
    val engineLoadPct: Double = 0.0,
    val coolantTempC: Double = 20.0,
    val intakeAirTempC: Double = 20.0,
    val ambientAirTempC: Double = 20.0,
    val mafGramsPerSec: Double = 0.0,
    val manifoldPressureKPa: Double = 100.0,
    val oilTempC: Double = 90.0,
    val timingAdvanceDeg: Double = 0.0,
    val barometricPressureKPa: Double = 100.0,
) {
    /** True when speed was updated within the last 15 s — stale values must not drive metrics. */
    val hasFreshSpeed: Boolean
        get() = speedUpdatedAt?.let { secondsSince(it) <= 15 && secondsSince(it) >= 0 } ?: false

    val hasFreshPower: Boolean
        get() = powerUpdatedAt?.let { secondsSince(it) in 0.0..15.0 } ?: false

    private fun secondsSince(then: Instant): Double = (timestamp.toEpochMilli() - then.toEpochMilli()) / 1000.0
}
