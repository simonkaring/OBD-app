package com.simonkaring.voltlink.core.telemetry

import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import java.time.Instant

/**
 * Catalogue of telemetry values that can appear on a dashboard tile, mirroring the iOS
 * `TelemetryMetric` enum (display names, units, dial ranges and decimal places included).
 */
enum class TelemetryMetric(
    val displayName: String,
    val unitSymbol: String,
    val rangeStart: Double,
    val rangeEnd: Double,
    val decimalPlaces: Int,
) {
    SPEED("Speed", "km/h", 0.0, 200.0, 0),
    POWER("Power", "kW", -50.0, 150.0, 1),
    SOC("State of Charge", "%", 0.0, 100.0, 0),
    SOH("State of Health", "%", 0.0, 100.0, 0),
    BATTERY_TEMP("HV Battery Temp", "°C", -20.0, 60.0, 0),
    AUX_12V("Auxiliary 12V", "V", 9.0, 15.0, 1),
    MOTOR_RPM("Motor RPM", "RPM", 0.0, 8000.0, 0),
    MOTOR_TORQUE("Motor Torque", "Nm", -100.0, 400.0, 0),
    FUEL_LEVEL("Fuel Level", "%", 0.0, 100.0, 0),
    THROTTLE_POSITION("Throttle Position", "%", 0.0, 100.0, 0),
    ENGINE_LOAD("Engine Load", "%", 0.0, 100.0, 0),
    COOLANT_TEMP("Coolant Temp", "°C", -20.0, 120.0, 0),
    INTAKE_AIR_TEMP("Intake Air Temp", "°C", -20.0, 60.0, 0),
    PACK_VOLTAGE("Pack Voltage", "V", 250.0, 450.0, 1),
    PACK_CURRENT("Pack Current", "A", -300.0, 300.0, 1),
    BATTERY_TEMP_MIN("Battery Temp Min", "°C", -20.0, 60.0, 0),
    BATTERY_TEMP_MAX("Battery Temp Max", "°C", -20.0, 60.0, 0),
    AMBIENT_AIR_TEMP("Ambient Air Temp", "°C", -20.0, 50.0, 0),
    MAF("Mass Air Flow", "g/s", 0.0, 200.0, 0),
    MANIFOLD_PRESSURE("Manifold Pressure", "kPa", 20.0, 120.0, 0),
    OIL_TEMP("Oil Temp", "°C", -20.0, 150.0, 0),
    TIMING_ADVANCE("Timing Advance", "°", -30.0, 60.0, 0),
    BAROMETRIC_PRESSURE("Barometric Pressure", "kPa", 20.0, 120.0, 0),
    INSTANT_EFFICIENCY("Live Consumption", "kWh/100km", -40.0, 40.0, 1),
    TRIP_AVERAGE_CONSUMPTION("Trip Average Consumption", "kWh/100km", -40.0, 40.0, 1),
    REGEN_POWER("Regen Power", "kW", 0.0, 100.0, 1),
    VEHICLE_RANGE("Vehicle Range", "km", 0.0, 600.0, 0),
    FRONT_LEFT_WHEEL_SPEED("Front Left Wheel Speed", "km/h", 0.0, 200.0, 0),
    FRONT_RIGHT_WHEEL_SPEED("Front Right Wheel Speed", "km/h", 0.0, 200.0, 0),
    REAR_LEFT_WHEEL_SPEED("Rear Left Wheel Speed", "km/h", 0.0, 200.0, 0),
    REAR_RIGHT_WHEEL_SPEED("Rear Right Wheel Speed", "km/h", 0.0, 200.0, 0),
    LONGITUDINAL_ACCELERATION("Longitudinal Acceleration", "g", -2.0, 2.0, 2),
    LATERAL_ACCELERATION("Lateral Acceleration", "g", -2.0, 2.0, 2),
    YAW_RATE("Yaw Rate", "g", -2.0, 2.0, 2),
    STEERING_ANGLE("Steering Angle", "°", -720.0, 720.0, 2),
    BRAKE_CYLINDER_PRESSURE("Brake Cylinder Pressure", "bar", 0.0, 100.0, 2),
    VACUUM_BRAKE_PRESSURE("Vacuum Brake Pressure", "bar", 0.0, 100.0, 2),
    AUX_12V_HIGH_DEFINITION("12V Voltage (High Definition)", "V", 0.0, 25.0, 2),
    CONVERTER_REQUESTED_VOLTAGE("DC Converter Requested Voltage", "V", 0.0, 25.0, 2),
    SERVICE_DISTANCE("Distance to Service", "km", 0.0, 60_000.0, 0),
    DRIVE_UNIT_TEMP("Drive Unit Temp", "°C", -40.0, 150.0, 0),
    MOTOR_TEMP("Motor Temp", "°C", -40.0, 150.0, 0),
    ;

    /** Metrics published only by the EQA OBDb community signal set. */
    val isCommunityMetric: Boolean
        get() = this in EQA_COMMUNITY_METRICS

    /** Normalization range used by dial/bar tiles. */
    val defaultRange: ClosedFloatingPointRange<Double> get() = rangeStart..rangeEnd

    // Temperature metrics still share a unit; this keeps UnitPreferences conversion in one place.
    val isTemperature: Boolean
        get() = this in TEMPERATURE_METRICS

    val isPercent: Boolean
        get() = this in PERCENT_METRICS

    val isPower: Boolean
        get() = this == POWER || this == REGEN_POWER

    val isDistance: Boolean
        get() = this == VEHICLE_RANGE || this == SERVICE_DISTANCE

    /** Consumption metrics are stated per 100 km and follow the distance unit. */
    val isEfficiency: Boolean
        get() = this == INSTANT_EFFICIENCY || this == TRIP_AVERAGE_CONSUMPTION

    /** Current value in SI units. Missing community values read as 0, like the iOS app. */
    fun value(snapshot: TelemetrySnapshot): Double = when (this) {
        SPEED -> snapshot.speedKmH
        POWER -> snapshot.powerKW
        SOC -> snapshot.stateOfChargePct
        SOH -> snapshot.stateOfHealthPct
        BATTERY_TEMP -> snapshot.batteryTempC
        AUX_12V -> snapshot.aux12VVolts
        MOTOR_RPM -> snapshot.motorRpm
        MOTOR_TORQUE -> snapshot.motorTorqueNm
        FUEL_LEVEL -> snapshot.fuelLevelPct
        THROTTLE_POSITION -> snapshot.throttlePositionPct
        ENGINE_LOAD -> snapshot.engineLoadPct
        COOLANT_TEMP -> snapshot.coolantTempC
        INTAKE_AIR_TEMP -> snapshot.intakeAirTempC
        PACK_VOLTAGE -> snapshot.voltageV
        PACK_CURRENT -> snapshot.currentA
        BATTERY_TEMP_MIN -> snapshot.batteryTempMinC
        BATTERY_TEMP_MAX -> snapshot.batteryTempMaxC
        AMBIENT_AIR_TEMP -> snapshot.ambientAirTempC
        MAF -> snapshot.mafGramsPerSec
        MANIFOLD_PRESSURE -> snapshot.manifoldPressureKPa
        OIL_TEMP -> snapshot.oilTempC
        TIMING_ADVANCE -> snapshot.timingAdvanceDeg
        BAROMETRIC_PRESSURE -> snapshot.barometricPressureKPa
        INSTANT_EFFICIENCY ->
            if (snapshot.speedKmH >= 5) (snapshot.powerKW / snapshot.speedKmH) * 100.0 else 0.0
        TRIP_AVERAGE_CONSUMPTION -> snapshot.tripAverageConsumption ?: 0.0
        REGEN_POWER ->
            if (snapshot.speedKmH >= 1 && !snapshot.isCharging) maxOf(0.0, -snapshot.powerKW) else 0.0
        VEHICLE_RANGE -> snapshot.vehicleRangeKm ?: 0.0
        else -> snapshot.communityValues?.get(this) ?: 0.0
    }

    /**
     * Whether the metric currently has a value worth showing. Derived metrics go stale with
     * their inputs so a dropped PID does not freeze a plausible-looking number on screen.
     */
    fun isAvailable(
        snapshot: TelemetrySnapshot,
        liveMetrics: Set<TelemetryMetric>,
        isDemoMode: Boolean = false,
        at: Instant = snapshot.timestamp,
    ): Boolean {
        if (this == TRIP_AVERAGE_CONSUMPTION) return snapshot.tripAverageConsumption != null
        if (!isDemoMode && this !in liveMetrics) return false
        fun fresh(then: Instant?): Boolean {
            if (then == null) return false
            val seconds = (at.toEpochMilli() - then.toEpochMilli()) / 1000.0
            return seconds in 0.0..15.0
        }
        return when (this) {
            INSTANT_EFFICIENCY ->
                fresh(snapshot.speedUpdatedAt) && fresh(snapshot.powerUpdatedAt) &&
                    snapshot.speedKmH >= 5 && !snapshot.isCharging
            REGEN_POWER -> fresh(snapshot.speedUpdatedAt) && fresh(snapshot.powerUpdatedAt)
            VEHICLE_RANGE -> snapshot.vehicleRangeKm != null && fresh(snapshot.vehicleRangeUpdatedAt)
            // Any value with its own domain stamp expires on that stamp; fields without one
            // (aux voltage, rpm, torque) are covered by the live-metric set above.
            else -> snapshot.updatedAt(this)?.let { fresh(it) } ?: true
        }
    }

    /** Applies [update] to [snapshot], returning the new snapshot or null when it does not decode. */
    fun applyTo(snapshot: TelemetrySnapshot, update: TelemetryUpdate, at: Instant = snapshot.timestamp): TelemetrySnapshot? =
        when (update) {
            is TelemetryUpdate.CommunityMetric ->
                if (update.metric == this) snapshot.copy(communityValues = (snapshot.communityValues ?: emptyMap()) + (this to update.value)) else null
            else -> null
        }

    companion object {
        val EQA_COMMUNITY_METRICS: Set<TelemetryMetric> = setOf(
            FRONT_LEFT_WHEEL_SPEED, FRONT_RIGHT_WHEEL_SPEED, REAR_LEFT_WHEEL_SPEED, REAR_RIGHT_WHEEL_SPEED,
            LONGITUDINAL_ACCELERATION, LATERAL_ACCELERATION, YAW_RATE, STEERING_ANGLE,
            BRAKE_CYLINDER_PRESSURE, VACUUM_BRAKE_PRESSURE, AUX_12V_HIGH_DEFINITION,
            CONVERTER_REQUESTED_VOLTAGE, SERVICE_DISTANCE, DRIVE_UNIT_TEMP, MOTOR_TEMP,
        )

        val TEMPERATURE_METRICS: Set<TelemetryMetric> = setOf(
            BATTERY_TEMP, BATTERY_TEMP_MIN, BATTERY_TEMP_MAX, COOLANT_TEMP, INTAKE_AIR_TEMP,
            AMBIENT_AIR_TEMP, OIL_TEMP, DRIVE_UNIT_TEMP, MOTOR_TEMP,
        )

        val PERCENT_METRICS: Set<TelemetryMetric> = setOf(
            SOC, SOH, FUEL_LEVEL, THROTTLE_POSITION, ENGINE_LOAD,
        )

        /** Re-adds derived metrics whose inputs are all live, and drops them otherwise. */
        fun includingDerivedMetrics(metrics: Set<TelemetryMetric>): Set<TelemetryMetric> {
            val result = (metrics - setOf(INSTANT_EFFICIENCY, REGEN_POWER)).toMutableSet()
            if (result.containsAll(setOf(SPEED, POWER))) {
                result.add(INSTANT_EFFICIENCY)
                result.add(REGEN_POWER)
            }
            return result
        }
    }
}
