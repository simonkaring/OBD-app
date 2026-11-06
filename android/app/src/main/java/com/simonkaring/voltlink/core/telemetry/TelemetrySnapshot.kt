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
    val communityUpdatedAt: Map<TelemetryMetric, Instant> = emptyMap(),
    /** Presentation-only value supplied by the active trip tracker. */
    val tripAverageConsumption: Double? = null,
    val stateOfChargePct: Double = 0.0,
    val socUpdatedAt: Instant? = null,
    val stateOfHealthPct: Double = 0.0,
    val sohUpdatedAt: Instant? = null,
    val batteryTempC: Double = 0.0,
    val batteryTempMinC: Double = 0.0,
    val batteryTempMaxC: Double = 0.0,
    val batteryTempUpdatedAt: Instant? = null,
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
    val coolantTempUpdatedAt: Instant? = null,
    val intakeAirTempC: Double = 20.0,
    val intakeAirTempUpdatedAt: Instant? = null,
    val ambientAirTempC: Double = 20.0,
    val ambientAirTempUpdatedAt: Instant? = null,
    val mafGramsPerSec: Double = 0.0,
    val manifoldPressureKPa: Double = 100.0,
    val oilTempC: Double = 90.0,
    val oilTempUpdatedAt: Instant? = null,
    val timingAdvanceDeg: Double = 0.0,
    val barometricPressureKPa: Double = 100.0,
) {
    /** True when speed was updated within the last 15 s — stale values must not drive metrics. */
    val hasFreshSpeed: Boolean
        get() = speedUpdatedAt?.let { secondsSince(it) <= 15 && secondsSince(it) >= 0 } ?: false

    val hasFreshPower: Boolean
        get() = powerUpdatedAt?.let { secondsSince(it) in 0.0..15.0 } ?: false

    /**
     * When [metric] last arrived, for every value the reducer stamps individually; null for
     * derived metrics and fields that carry no domain timestamp.
     */
    fun updatedAt(metric: TelemetryMetric): Instant? = when (metric) {
        TelemetryMetric.SPEED -> speedUpdatedAt
        TelemetryMetric.POWER -> powerUpdatedAt
        TelemetryMetric.SOC -> socUpdatedAt
        TelemetryMetric.SOH -> sohUpdatedAt
        TelemetryMetric.PACK_VOLTAGE -> voltageUpdatedAt
        TelemetryMetric.PACK_CURRENT -> currentUpdatedAt
        TelemetryMetric.VEHICLE_RANGE -> vehicleRangeUpdatedAt
        TelemetryMetric.BATTERY_TEMP,
        TelemetryMetric.BATTERY_TEMP_MIN,
        TelemetryMetric.BATTERY_TEMP_MAX,
        -> batteryTempUpdatedAt
        TelemetryMetric.COOLANT_TEMP -> coolantTempUpdatedAt
        TelemetryMetric.INTAKE_AIR_TEMP -> intakeAirTempUpdatedAt
        TelemetryMetric.AMBIENT_AIR_TEMP -> ambientAirTempUpdatedAt
        TelemetryMetric.OIL_TEMP -> oilTempUpdatedAt
        else -> communityUpdatedAt[metric]
    }

    private fun secondsSince(then: Instant): Double = (timestamp.toEpochMilli() - then.toEpochMilli()) / 1000.0
}
