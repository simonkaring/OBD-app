package com.simonkaring.voltlink.car

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import java.util.Locale
import kotlin.math.abs

/** Shown where a value is unknown, exactly like the phone's dials. */
internal const val CAR_PLACEHOLDER = "--"

/**
 * Colours of the phone's `MetricDial` (see `ui/theme/Theme`), as ARGB ints so this model stays
 * free of Android types: [CarDialRenderer] turns it into the bitmap a car template can show.
 */
internal object CarDialColors {
    val track = 0x1AFFFFFF
    val cyan = 0xFF00F0FF.toInt()
    val blue = 0xFF0073FF.toInt()
    val amber = 0xFFFF9F0A.toInt()
    val red = 0xFFFF453A.toInt()
    val green = 0xFF30D158.toInt()
    val textPrimary = 0xFFFFFFFF.toInt()
    val textSecondary = 0xB3FFFFFF.toInt()

    val power = listOf(cyan, amber, red)
    val regen = listOf(blue, green)
    val soc = listOf(green, cyan)
    val socLow = listOf(amber, red)
}

/**
 * One car dial: the centre text, its unit and the arc fill, mirroring the phone's dial tile.
 *
 * [fraction] runs 0..1 for a one-way gauge; for a [bidirectional] gauge it runs -1..1 with zero at
 * the top of the arc, so power draw fills towards the end and regen towards the start.
 */
internal data class CarDial(
    val valueText: String,
    val unitText: String?,
    val fraction: Double,
    val available: Boolean,
    val negative: Boolean = false,
    val bidirectional: Boolean = false,
    val colors: List<Int> = CarDialColors.soc,
) {
    /** Identity of the rendered pixels, so an unchanged value reuses its bitmap. */
    val key: String
        get() = "$available|$valueText|$unitText|$fraction|$negative|$bidirectional|" +
            colors.joinToString(",")
}

/** The dial for one telemetry metric, using the same range and gradient the phone dashboard uses. */
internal fun carDial(
    metric: TelemetryMetric,
    snapshot: TelemetrySnapshot,
    available: Boolean = true,
): CarDial {
    val value = metric.value(snapshot)
    val range = metric.defaultRange
    val span = range.endInclusive - range.start
    val bidirectional = metric == TelemetryMetric.POWER
    val usable = available && value.isFinite()
    val fraction = when {
        bidirectional && value >= 0 -> (value / maxOf(range.endInclusive, 0.0001)).coerceIn(0.0, 1.0)
        bidirectional -> (value / maxOf(abs(range.start), 0.0001)).coerceIn(-1.0, 0.0)
        span <= 0 -> 0.0
        else -> ((value - range.start) / span).coerceIn(0.0, 1.0)
    }
    return CarDial(
        valueText = if (usable) dialNumberText(value) else CAR_PLACEHOLDER,
        unitText = metric.unitSymbol,
        fraction = if (usable) fraction else 0.0,
        available = usable,
        negative = bidirectional && value < 0,
        bidirectional = bidirectional,
        colors = dialColors(metric, snapshot),
    )
}

/**
 * The phone dial's number rule: whole numbers from 100 up, one decimal below it, always unsigned
 * (the arc and colour carry the direction).
 */
private fun dialNumberText(value: Double): String =
    if (value >= 100) {
        String.format(Locale.US, "%.0f", abs(value))
    } else {
        String.format(Locale.US, "%.1f", abs(value)).removeSuffix(".0")
    }

/** Gradient per metric, matching the dashboard's `brushFor`. */
internal fun dialColors(metric: TelemetryMetric, snapshot: TelemetrySnapshot): List<Int> = when {
    metric == TelemetryMetric.POWER && snapshot.powerKW < 0 -> CarDialColors.regen
    metric == TelemetryMetric.POWER -> CarDialColors.power
    metric == TelemetryMetric.SOC && snapshot.stateOfChargePct < 20 -> CarDialColors.socLow
    else -> CarDialColors.soc
}

/**
 * Charging facts copied off `ChargingTracker.State`, so the charging tab is built (and tested)
 * without a tracker or a snapshot flow.
 */
internal data class CarChargingState(
    val isCharging: Boolean = false,
    val targetPercent: Int = 80,
    val secondsToTarget: Double? = null,
    val deliveredKWh: Double = 0.0,
    val sessionStartSocPct: Double? = null,
)

/** Charge power on a fixed 0–150 kW scale with the phone's power gradient. */
internal fun carChargePowerDial(powerKW: Double, isCharging: Boolean): CarDial {
    val usable = isCharging && powerKW.isFinite() && powerKW > 0.05
    return CarDial(
        valueText = if (usable) dialNumberText(powerKW) else CAR_PLACEHOLDER,
        unitText = TelemetryMetric.POWER.unitSymbol,
        fraction = if (usable) (powerKW / CHARGE_DIAL_MAX_KW).coerceIn(0.0, 1.0) else 0.0,
        available = usable,
        colors = CarDialColors.power,
    )
}

private const val CHARGE_DIAL_MAX_KW = 150.0

/**
 * Progress from the session's start state of charge towards the target, with the projected time
 * left in the middle — the phone's "time to target" stat drawn as a gauge.
 */
internal fun carTimeToTargetDial(charging: CarChargingState, socPct: Double, reachedText: String): CarDial {
    val start = charging.sessionStartSocPct ?: socPct
    val span = (charging.targetPercent - start).coerceAtLeast(1.0)
    val fraction = ((socPct - start) / span).coerceIn(0.0, 1.0)
    val remaining = charging.secondsToTarget
    return CarDial(
        valueText = when {
            !charging.isCharging || remaining == null -> CAR_PLACEHOLDER
            remaining <= 0.0 -> reachedText
            else -> carDurationText(remaining)
        },
        unitText = null,
        fraction = if (charging.isCharging) fraction else 0.0,
        available = charging.isCharging && remaining != null,
        colors = CarDialColors.soc,
    )
}

/** Hours and minutes, worded like the phone's charging screen. */
internal fun carDurationText(seconds: Double): String {
    val minutes = (seconds / 60).toInt().coerceAtLeast(1)
    return if (minutes >= 60) "${minutes / 60} h ${minutes % 60} min" else "$minutes min"
}

/** English fallback for callers without a Context; the car UI passes localized copy in. */
internal fun defaultHealthText(storedCodes: Int?): String = when {
    storedCodes == null -> "Not scanned"
    storedCodes == 0 -> "No stored codes"
    else -> "$storedCodes stored codes"
}
