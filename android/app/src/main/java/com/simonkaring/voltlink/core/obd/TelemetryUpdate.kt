package com.simonkaring.voltlink.core.obd

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric

/**
 * A decoded reading emitted by a vehicle profile. Mirrors the iOS `TelemetryUpdate` enum so
 * profiles port across without changing their decode math.
 */
sealed interface TelemetryUpdate {
    data class Speed(val kmh: Double) : TelemetryUpdate
    data class Power(val voltage: Double, val current: Double, val powerKW: Double) : TelemetryUpdate
    data class PackVoltage(val volts: Double) : TelemetryUpdate
    data class PackCurrent(val amps: Double) : TelemetryUpdate
    data class Soc(val percent: Double) : TelemetryUpdate
    data class Soh(val percent: Double) : TelemetryUpdate
    data class BatteryTemp(val min: Double, val max: Double, val avg: Double) : TelemetryUpdate
    data class Aux12V(val volts: Double) : TelemetryUpdate
    data class MotorStats(val rpm: Double, val torqueNm: Double) : TelemetryUpdate
    data class MotorRpm(val rpm: Double) : TelemetryUpdate
    data class MotorTorque(val torqueNm: Double) : TelemetryUpdate
    data class HvacPower(val kw: Double) : TelemetryUpdate
    /** [kwRate] is null when the profile only knows *that* the car is charging. */
    data class ChargingStats(val kwRate: Double?, val acOrDc: String) : TelemetryUpdate
    data class GenericPid(val mode: String, val pid: String, val rawValue: String) : TelemetryUpdate
    data class FuelLevel(val percent: Double) : TelemetryUpdate
    data class ThrottlePosition(val percent: Double) : TelemetryUpdate
    data class EngineLoad(val percent: Double) : TelemetryUpdate
    data class CoolantTemp(val celsius: Double) : TelemetryUpdate
    data class IntakeAirTemp(val celsius: Double) : TelemetryUpdate
    data class AmbientAirTemp(val celsius: Double) : TelemetryUpdate
    data class Maf(val gramsPerSec: Double) : TelemetryUpdate
    data class ManifoldPressure(val kPa: Double) : TelemetryUpdate
    data class OilTemp(val celsius: Double) : TelemetryUpdate
    data class TimingAdvance(val degrees: Double) : TelemetryUpdate
    data class BarometricPressure(val kPa: Double) : TelemetryUpdate
    data class VehicleRange(val km: Double) : TelemetryUpdate
    data class CommunityMetric(val metric: TelemetryMetric, val value: Double) : TelemetryUpdate
}

/** Adapter connection state, shared by the BLE manager, demo adapter and UI. */
sealed interface BleConnectionState {
    data object Disconnected : BleConnectionState
    data object Scanning : BleConnectionState
    data class Connecting(val deviceName: String) : BleConnectionState
    data class Ready(val deviceName: String) : BleConnectionState
    data object DemoMode : BleConnectionState
    data class Error(val message: String) : BleConnectionState

    val isConnected: Boolean
        get() = this is Ready || this is DemoMode
}
