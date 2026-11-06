package com.simonkaring.voltlink.companion

import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.ChargingCurveSample
import com.simonkaring.voltlink.core.telemetry.ChargingTimeEstimator
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.services.ChargingTracker
import com.simonkaring.voltlink.services.TripTracker
import java.time.Duration
import java.time.Instant

enum class CompanionConnection { DISCONNECTED, CONNECTING, STALE, LIVE, DEMO }
enum class CompanionCharging { DISCONNECTED, UNAVAILABLE, INACTIVE, ACTIVE, COMPLETE }

/** Read-only presentation data; no adapter, recording or persistence ownership. SI throughout. */
data class CompanionState(
    val connection: CompanionConnection,
    val metrics: Map<TelemetryMetric, Double>,
    val rangeKm: Double?,
    val rangeEstimated: Boolean,
    val capacityKWh: Double?,
    val tripDistanceKm: Double?,
    val tripSeconds: Long?,
    val tripConsumption: Double?,
    val charging: CompanionCharging,
    val chargePowerKW: Double?,
    val chargePowerEstimated: Boolean,
    val secondsTo80: Double?,
    val energyAddedKWh: Double?,
    val chargingSeconds: Long?,
    val costDKK: Double?,
)

fun companionState(
    snapshot: TelemetrySnapshot,
    liveMetrics: Set<TelemetryMetric>,
    supportedMetrics: Set<TelemetryMetric>,
    connection: BleConnectionState,
    demo: Boolean,
    capacityKWh: Double,
    trip: TripTracker.State,
    charging: ChargingTracker.State,
    priceDKKPerKWh: Double,
    now: Instant = Instant.now(),
): CompanionState {
    fun fresh(at: Instant?) = at != null && Duration.between(at, now).toMillis() in 0L..15_000L
    val connected = connection.isConnected
    val status = when {
        !connected -> when (connection) {
            BleConnectionState.Scanning, is BleConnectionState.Connecting -> CompanionConnection.CONNECTING
            else -> CompanionConnection.DISCONNECTED
        }
        !fresh(snapshot.timestamp) || liveMetrics.isEmpty() -> CompanionConnection.STALE
        demo -> CompanionConnection.DEMO
        else -> CompanionConnection.LIVE
    }
    val usable = status == CompanionConnection.LIVE || status == CompanionConnection.DEMO
    val metrics = liveMetrics.filter { metric ->
        usable && (demo || metric in supportedMetrics) &&
            metric.isAvailable(snapshot, liveMetrics, at = now)
    }.mapNotNull { metric ->
        metric.value(snapshot).takeIf { it.isFinite() }?.let { metric to it }
    }.toMap()
    val capacity = capacityKWh.takeIf { it.isFinite() && it > 0 }
    val average = trip.averageConsumption?.takeIf { trip.current != null && it.isFinite() }
    val reportedRange = metrics[TelemetryMetric.VEHICLE_RANGE]
    val estimatedRange = average?.takeIf { it > 0.1 }?.let { consumption ->
        metrics[TelemetryMetric.SOC]?.let { soc -> capacity?.let { soc / 100 * it / consumption * 100 } }
    }
    val chargePower = snapshot.chargePowerKW.takeIf {
        usable && fresh(snapshot.chargePowerUpdatedAt) && snapshot.chargePowerSource != null && it.isFinite() && it >= 0
    }
    val chargingStatus = when {
        !connected -> CompanionCharging.DISCONNECTED
        !usable || chargePower == null -> CompanionCharging.UNAVAILABLE
        charging.isCharging && snapshot.isCharging -> CompanionCharging.ACTIVE
        charging.lastCompletedTargetReached &&
            (metrics[TelemetryMetric.SOC] ?: -1.0) >= charging.targetPercent -> CompanionCharging.COMPLETE
        else -> CompanionCharging.INACTIVE
    }
    val session = charging.current
    val eta = if (chargingStatus == CompanionCharging.ACTIVE && chargePower != null && capacity != null) {
        metrics[TelemetryMetric.SOC]?.let { soc ->
            ChargingTimeEstimator.secondsToTarget(
                currentSoc = soc, targetSoc = 80.0, currentPowerKW = chargePower,
                capacityKWh = capacity,
                observedCurve = session?.samples.orEmpty().map { ChargingCurveSample(it.socPct, it.powerKW) },
            )
        }
    } else null
    val energy = session?.totalKWhDelivered?.takeIf { it.isFinite() && it >= 0 }
    fun elapsed(start: Instant, end: Instant?) = Duration.between(start, end ?: now).seconds.coerceAtLeast(0)
    return CompanionState(
        connection = status, metrics = metrics,
        rangeKm = reportedRange ?: estimatedRange, rangeEstimated = reportedRange == null,
        capacityKWh = capacity,
        tripDistanceKm = trip.current?.distanceKm, tripSeconds = trip.current?.let { elapsed(it.startTime, it.endTime) },
        tripConsumption = average, charging = chargingStatus,
        chargePowerKW = chargePower.takeIf { chargingStatus == CompanionCharging.ACTIVE },
        chargePowerEstimated = snapshot.chargePowerSource == com.simonkaring.voltlink.core.telemetry.ChargePowerSource.SOC_ESTIMATE,
        secondsTo80 = eta?.takeIf { it.isFinite() && it >= 0 }, energyAddedKWh = energy,
        chargingSeconds = session?.let { elapsed(it.startTime, it.endTime) },
        costDKK = energy?.let { kWh -> priceDKKPerKWh.takeIf { it.isFinite() && it > 0 }?.times(kWh) },
    )
}
