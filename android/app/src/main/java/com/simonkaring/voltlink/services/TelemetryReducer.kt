package com.simonkaring.voltlink.services

import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.telemetry.ChargePowerSource
import com.simonkaring.voltlink.core.telemetry.ChargingPowerEstimator
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetryPlausibility
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import java.time.Instant

/**
 * Applies decoded [TelemetryUpdate]s to a [TelemetrySnapshot]. This is the Android home of
 * the update semantics in the iOS `VehicleDataManager`: plausibility gating, pack power
 * recombination, charging permission, and SoC-slope charge estimation.
 */
class TelemetryReducer(private var capacityKWh: Double) {
    var snapshot: TelemetrySnapshot = TelemetrySnapshot()
        private set

    var liveMetrics: Set<TelemetryMetric> = emptySet()
        private set

    private val chargingEstimator = ChargingPowerEstimator()
    private var explicitChargingStatus: Pair<Boolean, Instant>? = null
    private var obdSpeedUpdatedAt: Instant? = null
    private var externalSpeedUpdatedAt: Instant? = null

    fun updateCapacity(kWh: Double) {
        capacityKWh = kWh
    }

    /** Drops the snapshot along with its validity, for when the telemetry source changes. */
    fun reset() {
        snapshot = TelemetrySnapshot()
        explicitChargingStatus = null
        resetValidity()
    }

    fun resetValidity() {
        liveMetrics = emptySet()
        obdSpeedUpdatedAt = null
        externalSpeedUpdatedAt = null
        chargingEstimator.reset()
    }

    fun apply(update: TelemetryUpdate, timestamp: Instant = Instant.now(), sourceCommand: String? = null): Boolean {
        if (!TelemetryPlausibility.isPlausible(update)) return false
        var snap = snapshot.copy(timestamp = timestamp)
        val socAt = snap.socUpdatedAt
        if (socAt != null && timestamp.toEpochMilli() - socAt.toEpochMilli() > 15_000) {
            snap = chargingEstimator.clear(snap)
            chargingEstimator.reset()
        }

        val updatedMetrics = metricsFor(update).toMutableSet()
        when (update) {
            is TelemetryUpdate.Speed -> {
                if (snap.speedUpdatedAt != null && timestamp < snap.speedUpdatedAt) return false
                obdSpeedUpdatedAt = timestamp
                externalSpeedUpdatedAt = null
                snap = snap.copy(speedKmH = update.kmh, speedUpdatedAt = timestamp)
                if (update.kmh > 1.0) {
                    chargingEstimator.reset()
                    // Moving means not plugged in: regen is not charging.
                    snap = chargingEstimator.clear(snap).copy(isCharging = false, chargePowerKW = 0.0)
                }
            }
            is TelemetryUpdate.Power -> {
                snap = chargingEstimator.clear(snap).copy(
                    voltageV = update.voltage,
                    currentA = update.current,
                    powerKW = update.powerKW,
                    voltageUpdatedAt = timestamp,
                    currentUpdatedAt = timestamp,
                    powerUpdatedAt = timestamp,
                )
                // Negative pack current = energy into the pack. Only charging (not regen)
                // when the car is parked.
                if (update.current < -1.0 && chargingPermitted(snap)) {
                    snap = snap.copy(isCharging = true, chargePowerKW = kotlin.math.abs(update.powerKW))
                } else {
                    snap = snap.copy(isCharging = false, chargePowerKW = 0.0)
                }
                snap = snap.copy(chargePowerSource = ChargePowerSource.MEASURED, chargePowerUpdatedAt = timestamp)
            }
            is TelemetryUpdate.PackVoltage -> {
                snap = snap.copy(voltageV = update.volts, voltageUpdatedAt = timestamp)
                val combined = updatePackPower(snap, updatedMetrics)
                snap = combined.first
                updatedMetrics += combined.second
            }
            is TelemetryUpdate.PackCurrent -> {
                snap = snap.copy(currentA = update.amps, currentUpdatedAt = timestamp)
                val combined = updatePackPower(snap, updatedMetrics)
                snap = combined.first
                updatedMetrics += combined.second
            }
            is TelemetryUpdate.Soc -> {
                snap = snap.copy(stateOfChargePct = update.percent, socUpdatedAt = timestamp)
                snap = chargingEstimator.update(
                    soc = update.percent,
                    capacityKWh = capacityKWh,
                    timestamp = timestamp,
                    chargingPermitted = chargingPermitted(snap),
                    snapshot = snap,
                )
            }
            is TelemetryUpdate.Soh -> snap = snap.copy(stateOfHealthPct = update.percent, sohUpdatedAt = timestamp)
            is TelemetryUpdate.BatteryTemp -> snap = snap.copy(
                batteryTempC = update.avg,
                batteryTempMinC = update.min,
                batteryTempMaxC = update.max,
                batteryTempUpdatedAt = timestamp,
            )
            is TelemetryUpdate.Aux12V -> snap = snap.copy(aux12VVolts = update.volts)
            is TelemetryUpdate.MotorStats -> snap = snap.copy(motorRpm = update.rpm, motorTorqueNm = update.torqueNm)
            is TelemetryUpdate.MotorRpm -> snap = snap.copy(motorRpm = update.rpm)
            is TelemetryUpdate.MotorTorque -> snap = snap.copy(motorTorqueNm = update.torqueNm)
            is TelemetryUpdate.HvacPower -> snap = snap.copy(hvacPowerKW = update.kw)
            is TelemetryUpdate.ChargingStats -> {
                val kw = update.kwRate
                explicitChargingStatus = (kw?.let { it > 0.5 } ?: true) to timestamp
                snap = if (kw != null) {
                    snap.copy(
                        isCharging = kw > 0.5,
                        chargePowerKW = kw,
                        chargePowerUpdatedAt = timestamp,
                        chargePowerSource = ChargePowerSource.MEASURED,
                    )
                } else {
                    // The status bit says charging but the profile cannot measure the rate:
                    // flag it and let the SoC slope or a pack-power PID fill in the kW.
                    snap.copy(isCharging = true)
                }
            }
            is TelemetryUpdate.FuelLevel -> snap = snap.copy(fuelLevelPct = update.percent)
            is TelemetryUpdate.ThrottlePosition -> snap = snap.copy(throttlePositionPct = update.percent)
            is TelemetryUpdate.EngineLoad -> snap = snap.copy(engineLoadPct = update.percent)
            is TelemetryUpdate.CoolantTemp -> snap = snap.copy(coolantTempC = update.celsius, coolantTempUpdatedAt = timestamp)
            is TelemetryUpdate.IntakeAirTemp -> snap = snap.copy(intakeAirTempC = update.celsius, intakeAirTempUpdatedAt = timestamp)
            is TelemetryUpdate.AmbientAirTemp -> snap = snap.copy(ambientAirTempC = update.celsius, ambientAirTempUpdatedAt = timestamp)
            is TelemetryUpdate.Maf -> snap = snap.copy(mafGramsPerSec = update.gramsPerSec)
            is TelemetryUpdate.ManifoldPressure -> snap = snap.copy(manifoldPressureKPa = update.kPa)
            is TelemetryUpdate.OilTemp -> snap = snap.copy(oilTempC = update.celsius, oilTempUpdatedAt = timestamp)
            is TelemetryUpdate.TimingAdvance -> snap = snap.copy(timingAdvanceDeg = update.degrees)
            is TelemetryUpdate.BarometricPressure -> snap = snap.copy(barometricPressureKPa = update.kPa)
            is TelemetryUpdate.VehicleRange -> snap = snap.copy(
                vehicleRangeKm = update.km,
                vehicleRangeUpdatedAt = timestamp,
            )
            is TelemetryUpdate.CommunityMetric -> {
                val values = (snap.communityValues ?: emptyMap()).toMutableMap()
                values[update.metric] = update.value
                snap = snap.copy(
                    communityValues = values,
                    communityUpdatedAt = snap.communityUpdatedAt + (update.metric to timestamp),
                )
            }
            is TelemetryUpdate.GenericPid -> Unit
        }

        if (!chargingPermitted(snap)) {
            snap = snap.copy(isCharging = false, chargePowerKW = 0.0)
            if (snap.chargePowerSource == ChargePowerSource.SOC_ESTIMATE) snap = chargingEstimator.clear(snap)
        }

        snapshot = snap
        liveMetrics = TelemetryMetric.includingDerivedMetrics(liveMetrics + updatedMetrics)
        return true
    }

    /** Applies a batch, publishing once; returns true when at least one update landed. */
    fun applyAll(updates: List<TelemetryUpdate>, timestamp: Instant = Instant.now(), sourceCommand: String? = null): Boolean {
        var applied = false
        for (update in updates) {
            if (apply(update, timestamp, sourceCommand)) applied = true
        }
        return applied
    }

    fun needsExternalSpeed(now: Instant = Instant.now()): Boolean {
        val at = obdSpeedUpdatedAt ?: return true
        val age = (now.toEpochMilli() - at.toEpochMilli()) / 1000.0
        return age !in 0.0..15.0
    }

    fun applyExternalSpeed(speedKmH: Double, timestamp: Instant = Instant.now()) {
        val now = Instant.now()
        val age = (now.toEpochMilli() - timestamp.toEpochMilli()) / 1000.0
        if (age !in 0.0..15.0 || !needsExternalSpeed(timestamp)) return
        if (!TelemetryPlausibility.isPlausible(TelemetryUpdate.Speed(speedKmH))) return
        externalSpeedUpdatedAt = timestamp
        snapshot = snapshot.copy(speedKmH = speedKmH, speedUpdatedAt = timestamp)
        liveMetrics = TelemetryMetric.includingDerivedMetrics(liveMetrics + TelemetryMetric.SPEED)
    }

    fun clearExternalSpeed() {
        if (externalSpeedUpdatedAt == null) return
        externalSpeedUpdatedAt = null
        snapshot = snapshot.copy(speedKmH = 0.0, speedUpdatedAt = null)
        liveMetrics = TelemetryMetric.includingDerivedMetrics(liveMetrics - TelemetryMetric.SPEED)
    }

    /** Whether the pack may currently be charging, per speed and any explicit status bit. */
    fun chargingPermitted(snapshot: TelemetrySnapshot): Boolean {
        if (snapshot.hasFreshSpeed && snapshot.speedKmH >= 1) return false
        val status = explicitChargingStatus
        if (status != null) {
            val age = kotlin.math.abs(snapshot.timestamp.toEpochMilli() - status.second.toEpochMilli())
            if (age <= 15_000) return status.first
        }
        return snapshot.hasFreshSpeed && snapshot.speedKmH < 1
    }

    /** Recombines pack power once both voltage and current are fresh; returns new metrics. */
    private fun updatePackPower(
        snapshot: TelemetrySnapshot,
        updatedMetrics: MutableSet<TelemetryMetric>,
    ): Pair<TelemetrySnapshot, Set<TelemetryMetric>> {
        val available = liveMetrics + updatedMetrics
        val voltageAt = snapshot.voltageUpdatedAt
        val currentAt = snapshot.currentUpdatedAt
        if (TelemetryMetric.PACK_VOLTAGE !in available || TelemetryMetric.PACK_CURRENT !in available ||
            voltageAt == null || currentAt == null
        ) {
            return snapshot to emptySet()
        }
        val stamp = snapshot.timestamp.toEpochMilli()
        val voltageFresh = (stamp - voltageAt.toEpochMilli()) / 1000.0 in 0.0..15.0
        val currentFresh = (stamp - currentAt.toEpochMilli()) / 1000.0 in 0.0..15.0
        if (!voltageFresh || !currentFresh) return snapshot to emptySet()

        var snap = chargingEstimator.clear(snapshot)
        val power = snap.voltageV * snap.currentA / 1000.0
        // Power is only as fresh as its oldest input.
        val powerAt = if (voltageAt < currentAt) voltageAt else currentAt
        snap = snap.copy(powerKW = power, powerUpdatedAt = powerAt)
        if (snap.currentA < -1.0 && chargingPermitted(snap)) {
            snap = snap.copy(isCharging = true, chargePowerKW = kotlin.math.abs(power))
        } else {
            snap = snap.copy(isCharging = false, chargePowerKW = 0.0)
        }
        snap = snap.copy(
            chargePowerUpdatedAt = snap.timestamp,
            chargePowerSource = ChargePowerSource.MEASURED,
        )
        return snap to setOf(TelemetryMetric.POWER)
    }

    /** Metrics a single update contributes, used by the manager's miss bookkeeping. */
    fun metricsFor(update: TelemetryUpdate): Set<TelemetryMetric> = when (update) {
        is TelemetryUpdate.Speed -> setOf(TelemetryMetric.SPEED)
        is TelemetryUpdate.Power -> setOf(
            TelemetryMetric.POWER, TelemetryMetric.PACK_VOLTAGE, TelemetryMetric.PACK_CURRENT,
        )
        is TelemetryUpdate.PackVoltage -> setOf(TelemetryMetric.PACK_VOLTAGE)
        is TelemetryUpdate.PackCurrent -> setOf(TelemetryMetric.PACK_CURRENT)
        is TelemetryUpdate.Soc -> setOf(TelemetryMetric.SOC)
        is TelemetryUpdate.Soh -> setOf(TelemetryMetric.SOH)
        is TelemetryUpdate.BatteryTemp -> setOf(
            TelemetryMetric.BATTERY_TEMP, TelemetryMetric.BATTERY_TEMP_MIN, TelemetryMetric.BATTERY_TEMP_MAX,
        )
        is TelemetryUpdate.Aux12V -> setOf(TelemetryMetric.AUX_12V)
        is TelemetryUpdate.MotorStats -> setOf(TelemetryMetric.MOTOR_RPM, TelemetryMetric.MOTOR_TORQUE)
        is TelemetryUpdate.MotorRpm -> setOf(TelemetryMetric.MOTOR_RPM)
        is TelemetryUpdate.MotorTorque -> setOf(TelemetryMetric.MOTOR_TORQUE)
        is TelemetryUpdate.FuelLevel -> setOf(TelemetryMetric.FUEL_LEVEL)
        is TelemetryUpdate.ThrottlePosition -> setOf(TelemetryMetric.THROTTLE_POSITION)
        is TelemetryUpdate.EngineLoad -> setOf(TelemetryMetric.ENGINE_LOAD)
        is TelemetryUpdate.CoolantTemp -> setOf(TelemetryMetric.COOLANT_TEMP)
        is TelemetryUpdate.IntakeAirTemp -> setOf(TelemetryMetric.INTAKE_AIR_TEMP)
        is TelemetryUpdate.AmbientAirTemp -> setOf(TelemetryMetric.AMBIENT_AIR_TEMP)
        is TelemetryUpdate.Maf -> setOf(TelemetryMetric.MAF)
        is TelemetryUpdate.ManifoldPressure -> setOf(TelemetryMetric.MANIFOLD_PRESSURE)
        is TelemetryUpdate.OilTemp -> setOf(TelemetryMetric.OIL_TEMP)
        is TelemetryUpdate.TimingAdvance -> setOf(TelemetryMetric.TIMING_ADVANCE)
        is TelemetryUpdate.BarometricPressure -> setOf(TelemetryMetric.BAROMETRIC_PRESSURE)
        is TelemetryUpdate.VehicleRange -> setOf(TelemetryMetric.VEHICLE_RANGE)
        is TelemetryUpdate.CommunityMetric -> setOf(update.metric)
        is TelemetryUpdate.HvacPower, is TelemetryUpdate.ChargingStats, is TelemetryUpdate.GenericPid -> emptySet()
    }
}
