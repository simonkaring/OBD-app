package com.simonkaring.voltlink.core.telemetry

import kotlin.math.exp
import kotlin.math.min

/** A charge-power reading placed on the state-of-charge axis. */
data class ChargingCurveSample(val socPct: Double, val powerKW: Double)

/**
 * Projects remaining charging time by integrating energy band-by-band instead of dividing
 * once by the live rate — a straight division is badly wrong on a tapering DC session.
 * Port of the iOS `ChargingTimeEstimator`.
 */
object ChargingTimeEstimator {
    const val DC_POWER_THRESHOLD_KW = 22.0
    const val TAPER_START_SOC = 80.0
    const val TAPER_FLOOR_RATIO = 0.2
    const val TAPER_DECAY_SOC = 6.0
    const val MAXIMUM_ESTIMATE_SECONDS = 24 * 3600.0

    /** Seconds needed to charge from [currentSoc] to [targetSoc], or null for bad inputs. */
    fun secondsToTarget(
        currentSoc: Double,
        targetSoc: Double,
        currentPowerKW: Double,
        capacityKWh: Double,
        observedCurve: List<ChargingCurveSample> = emptyList(),
    ): Double? {
        if (!currentSoc.isFinite() || !targetSoc.isFinite() || !currentPowerKW.isFinite() || !capacityKWh.isFinite()) return null
        if (currentSoc !in 0.0..100.0 || targetSoc !in 0.0..100.0) return null
        if (capacityKWh <= 0 || currentPowerKW <= 0.5) return null
        if (targetSoc <= currentSoc) return 0.0

        var seconds = 0.0
        var soc = currentSoc
        while (soc < targetSoc - 0.0001) {
            val bandEnd = min(targetSoc, soc + 1.0)
            val power = projectedPowerKW((soc + bandEnd) / 2, currentSoc, currentPowerKW, observedCurve)
            if (!power.isFinite() || power <= 0.05) return null
            val energyKWh = capacityKWh * (bandEnd - soc) / 100.0
            seconds += energyKWh / power * 3600.0
            if (!seconds.isFinite() || seconds > MAXIMUM_ESTIMATE_SECONDS) return null
            soc = bandEnd
        }
        return seconds
    }

    /** Charge rate expected at a future state of charge. */
    fun projectedPowerKW(
        soc: Double,
        currentSoc: Double,
        currentPowerKW: Double,
        observedCurve: List<ChargingCurveSample>,
    ): Double {
        if (soc <= currentSoc || currentPowerKW <= DC_POWER_THRESHOLD_KW) return currentPowerKW

        val slope = observedTaperSlope(observedCurve)
        if (slope != null) {
            val projected = currentPowerKW + slope * (soc - currentSoc)
            val floor = maxOf(0.5, currentPowerKW * 0.05)
            return min(currentPowerKW, maxOf(floor, projected))
        }

        if (soc <= TAPER_START_SOC) return currentPowerKW
        val ratio = TAPER_FLOOR_RATIO + (1.0 - TAPER_FLOOR_RATIO) * exp(-(soc - TAPER_START_SOC) / TAPER_DECAY_SOC)
        return currentPowerKW * ratio
    }

    /** kW-per-percent slope from the newest measurable part of the curve, if falling. */
    fun observedTaperSlope(curve: List<ChargingCurveSample>): Double? {
        val readings = curve
            .filter { it.socPct.isFinite() && it.powerKW.isFinite() && it.socPct > 0 && it.powerKW > 0 }
            .sortedBy { it.socPct }
        val last = readings.lastOrNull() ?: return null
        val previous = readings.lastOrNull { last.socPct - it.socPct >= 0.5 } ?: return null
        if (last.socPct <= previous.socPct) return null
        val slope = (last.powerKW - previous.powerKW) / (last.socPct - previous.socPct)
        return if (slope.isFinite() && slope < 0) slope else null
    }
}
