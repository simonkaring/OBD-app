package com.simonkaring.voltlink.ui

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.DistanceUnit
import com.simonkaring.voltlink.data.PowerUnit
import com.simonkaring.voltlink.data.TemperatureUnit

/** Display-unit bundle: telemetry stays SI, conversion happens only at render time. */
data class UnitPrefs(
    val distance: DistanceUnit = DistanceUnit.KILOMETERS,
    val temperature: TemperatureUnit = TemperatureUnit.CELSIUS,
    val power: PowerUnit = PowerUnit.KILOWATT,
) {
    fun value(metric: TelemetryMetric, snapshot: TelemetrySnapshot): Double {
        val raw = metric.value(snapshot)
        return when {
            metric == TelemetryMetric.SPEED -> if (distance == DistanceUnit.MILES) raw * 0.621371 else raw
            metric.isDistance -> if (distance == DistanceUnit.MILES) raw * 0.621371 else raw
            metric.isTemperature -> if (temperature == TemperatureUnit.FAHRENHEIT) raw * 9.0 / 5.0 + 32.0 else raw
            metric.isPower -> if (power == PowerUnit.HORSEPOWER) raw * 1.34102 else raw
            else -> raw
        }
    }

    fun unit(metric: TelemetryMetric): String = when {
        metric == TelemetryMetric.SPEED -> if (distance == DistanceUnit.MILES) "mph" else "km/h"
        metric.isDistance -> if (distance == DistanceUnit.MILES) "mi" else "km"
        metric.isTemperature -> temperature.label
        metric.isPower -> power.label
        else -> metric.unitSymbol
    }

    fun speedValue(kmh: Double): Double = if (distance == DistanceUnit.MILES) kmh * 0.621371 else kmh

    val speedUnit: String get() = if (distance == DistanceUnit.MILES) "mph" else "km/h"

    val distanceUnitLabel: String get() = if (distance == DistanceUnit.MILES) "mi" else "km"

    fun range(metric: TelemetryMetric): ClosedFloatingPointRange<Double> {
        var start = metric.rangeStart
        var end = metric.rangeEnd
        when {
            metric == TelemetryMetric.SPEED || metric.isDistance -> if (distance == DistanceUnit.MILES) {
                start *= 0.621371
                end *= 0.621371
            }
            metric.isTemperature -> if (temperature == TemperatureUnit.FAHRENHEIT) {
                start = start * 9.0 / 5.0 + 32.0
                end = end * 9.0 / 5.0 + 32.0
            }
            metric.isPower -> if (power == PowerUnit.HORSEPOWER) {
                start *= 1.34102
                end *= 1.34102
            }
        }
        return start..end
    }
}
