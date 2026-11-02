package com.simonkaring.voltlink.car

import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import java.util.Locale

/**
 * The four values the car pane shows, already formatted. Kept free of Android types so the
 * templates are unit-tested without an instrumented run.
 */
data class CarTelemetrySummary(
    val status: String,
    val stateOfCharge: String,
    val power: String,
    val speed: String,
    val range: String,
) {
    val title: String get() = "VoltLink · $status"

    companion object {
        private const val PLACEHOLDER = "—"

        fun of(snapshot: TelemetrySnapshot, isDemoMode: Boolean, connection: BleConnectionState): CarTelemetrySummary {
            val status = when {
                isDemoMode -> "Demo"
                connection is BleConnectionState.Ready -> connection.deviceName
                connection is BleConnectionState.Scanning -> "Scanning"
                connection is BleConnectionState.Connecting -> "Connecting"
                connection is BleConnectionState.Error -> "Adapter offline"
                else -> "No adapter"
            }
            val powerKW = if (snapshot.isCharging) snapshot.chargePowerKW else snapshot.powerKW
            return CarTelemetrySummary(
                status = status,
                stateOfCharge = if (snapshot.stateOfChargePct <= 0.0) {
                    PLACEHOLDER
                } else {
                    String.format(Locale.US, "%.0f %%", snapshot.stateOfChargePct)
                },
                power = if (powerKW == 0.0) PLACEHOLDER else String.format(Locale.US, "%.1f kW", powerKW),
                speed = String.format(Locale.US, "%.0f km/h", snapshot.speedKmH),
                range = snapshot.vehicleRangeKm?.let { String.format(Locale.US, "%.0f km", it) } ?: PLACEHOLDER,
            )
        }
    }
}

/** English fallback for callers without a Context; the car UI passes localized copy in. */
fun defaultHealthText(storedCodes: Int?): String = when {
    storedCodes == null -> "Not scanned"
    storedCodes == 0 -> "No stored codes"
    else -> "$storedCodes stored codes"
}

/**
 * Formatted value for one configured car row. The four driving rows reuse the summary strings,
 * every other metric falls back to its own SI value and unit; the health row reports the last
 * DTC scan instead of telemetry, which is why [storedCodes] is null until a scan has run.
 */
fun carRowValue(
    kind: CarTileKind,
    summary: CarTelemetrySummary,
    snapshot: TelemetrySnapshot,
    storedCodes: Int?,
    healthText: (Int?) -> String = ::defaultHealthText,
): String =
    when (kind) {
        CarTileKind.Health -> healthText(storedCodes)
        is CarTileKind.Metric -> when (kind.metric) {
            TelemetryMetric.SOC -> summary.stateOfCharge
            TelemetryMetric.POWER -> summary.power
            TelemetryMetric.SPEED -> summary.speed
            TelemetryMetric.VEHICLE_RANGE -> summary.range
            else -> {
                val value = kind.metric.value(snapshot)
                if (value.isFinite()) {
                    String.format(Locale.US, "%.${kind.metric.decimalPlaces}f %s", value, kind.metric.unitSymbol)
                } else {
                    "—"
                }
            }
        }
    }
