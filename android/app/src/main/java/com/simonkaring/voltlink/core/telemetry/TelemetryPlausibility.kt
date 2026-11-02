package com.simonkaring.voltlink.core.telemetry

import com.simonkaring.voltlink.core.obd.TelemetryUpdate

/**
 * Physically plausible bounds per decoded quantity. Several profiles carry unverified
 * community scalings; rejecting out-of-range values here makes a wrong decode show up as
 * missing data instead of garbage on the dashboard.
 */
object TelemetryPlausibility {
    fun isPlausible(update: TelemetryUpdate): Boolean {
        fun ok(value: Double, range: ClosedFloatingPointRange<Double>) =
            value.isFinite() && value in range

        return when (update) {
            is TelemetryUpdate.Speed -> ok(update.kmh, 0.0..400.0)
            is TelemetryUpdate.Power ->
                ok(update.voltage, 0.0..1000.0) && ok(update.current, -1500.0..1500.0) &&
                    ok(update.powerKW, -1000.0..1000.0)
            is TelemetryUpdate.PackVoltage -> ok(update.volts, 0.0..1000.0)
            is TelemetryUpdate.PackCurrent -> ok(update.amps, -1500.0..1500.0)
            is TelemetryUpdate.Soc -> ok(update.percent, 0.0..100.0)
            is TelemetryUpdate.Soh -> ok(update.percent, 0.0..100.0)
            is TelemetryUpdate.BatteryTemp ->
                ok(update.min, -50.0..100.0) && ok(update.max, -50.0..100.0) && ok(update.avg, -50.0..100.0)
            is TelemetryUpdate.Aux12V -> ok(update.volts, 0.0..36.0)
            is TelemetryUpdate.MotorStats ->
                ok(update.rpm, -30_000.0..30_000.0) && ok(update.torqueNm, -5_000.0..5_000.0)
            is TelemetryUpdate.MotorRpm -> ok(update.rpm, -30_000.0..30_000.0)
            is TelemetryUpdate.MotorTorque -> ok(update.torqueNm, -5_000.0..5_000.0)
            is TelemetryUpdate.HvacPower -> ok(update.kw, -50.0..50.0)
            is TelemetryUpdate.ChargingStats -> update.kwRate?.let { ok(it, 0.0..600.0) } ?: true
            is TelemetryUpdate.FuelLevel -> ok(update.percent, 0.0..100.0)
            is TelemetryUpdate.ThrottlePosition -> ok(update.percent, 0.0..100.0)
            is TelemetryUpdate.EngineLoad -> ok(update.percent, 0.0..100.0)
            is TelemetryUpdate.CoolantTemp -> ok(update.celsius, -50.0..250.0)
            is TelemetryUpdate.IntakeAirTemp -> ok(update.celsius, -50.0..200.0)
            is TelemetryUpdate.AmbientAirTemp -> ok(update.celsius, -60.0..80.0)
            is TelemetryUpdate.Maf -> ok(update.gramsPerSec, 0.0..700.0)
            is TelemetryUpdate.ManifoldPressure -> ok(update.kPa, 0.0..500.0)
            is TelemetryUpdate.OilTemp -> ok(update.celsius, -50.0..250.0)
            is TelemetryUpdate.TimingAdvance -> ok(update.degrees, -70.0..70.0)
            is TelemetryUpdate.BarometricPressure -> ok(update.kPa, 0.0..300.0)
            is TelemetryUpdate.VehicleRange -> ok(update.km, 0.0..1000.0)
            is TelemetryUpdate.CommunityMetric -> when (update.metric) {
                TelemetryMetric.FRONT_LEFT_WHEEL_SPEED,
                TelemetryMetric.FRONT_RIGHT_WHEEL_SPEED,
                TelemetryMetric.REAR_LEFT_WHEEL_SPEED,
                TelemetryMetric.REAR_RIGHT_WHEEL_SPEED,
                -> ok(update.value, 0.0..400.0)
                TelemetryMetric.LONGITUDINAL_ACCELERATION,
                TelemetryMetric.LATERAL_ACCELERATION,
                TelemetryMetric.YAW_RATE,
                -> ok(update.value, -10.0..10.0)
                TelemetryMetric.STEERING_ANGLE -> ok(update.value, -3600.0..3600.0)
                TelemetryMetric.BRAKE_CYLINDER_PRESSURE,
                TelemetryMetric.VACUUM_BRAKE_PRESSURE,
                -> ok(update.value, -500.0..500.0)
                TelemetryMetric.AUX_12V_HIGH_DEFINITION,
                TelemetryMetric.CONVERTER_REQUESTED_VOLTAGE,
                -> ok(update.value, 0.0..36.0)
                TelemetryMetric.SERVICE_DISTANCE -> ok(update.value, 0.0..65_535.0)
                TelemetryMetric.DRIVE_UNIT_TEMP, TelemetryMetric.MOTOR_TEMP -> ok(update.value, -50.0..250.0)
                else -> false
            }
            is TelemetryUpdate.GenericPid -> true
        }
    }
}
