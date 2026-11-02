package com.simonkaring.voltlink.core.vehicles

import com.simonkaring.voltlink.core.obd.IsoTp
import com.simonkaring.voltlink.core.obd.ObdLogEntry
import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.Locale

/**
 * A shareable package of the commands VoltLink decoded for one vehicle.
 *
 * The bundled profiles come from community catalogs (ABRP, OVMS, OBDb), so this is the way
 * back: every command that decoded to a known metric, the response it decoded from, and the
 * decoded values, so a maintainer can review a decoding without replaying a whole capture.
 * Same document shape as the iOS `CommunityPIDContribution`.
 */
data class CommunityPidContribution(
    val vehicleName: String,
    val profileId: String,
    val appVersion: String,
    val generatedAt: Instant,
    val notes: String = "",
    val entries: List<Entry>,
) {
    data class Metric(val name: String, val unit: String, val value: Double)

    data class Entry(
        val command: String,
        val response: String,
        /** How many times this command decoded successfully in the exported log. */
        val observations: Int,
        val metrics: List<Metric>,
    )

    val metricCount: Int get() = entries.sumOf { it.metrics.size }

    val suggestedFilename: String
        get() {
            val slug = vehicleName.lowercase(Locale.US)
                .map { if (it.isLetterOrDigit()) it else '-' }
                .joinToString("")
                .split('-')
                .filter { it.isNotEmpty() }
                .joinToString("-")
            return "VoltLink-PID-Contribution-${slug.ifEmpty { "vehicle" }}.json"
        }

    /** Pretty-printed JSON with sorted keys and an ISO 8601 timestamp. */
    fun json(): String {
        val document = buildJsonObject {
            put("appVersion", appVersion)
            put(
                "entries",
                buildJsonArray {
                    entries.forEach { entry ->
                        add(
                            buildJsonObject {
                                put("command", entry.command)
                                put(
                                    "metrics",
                                    buildJsonArray {
                                        entry.metrics.forEach { metric ->
                                            add(
                                                buildJsonObject {
                                                    put("name", metric.name)
                                                    put("unit", metric.unit)
                                                    put("value", metric.value)
                                                },
                                            )
                                        }
                                    },
                                )
                                put("observations", entry.observations)
                                put("response", entry.response)
                            },
                        )
                    }
                },
            )
            put("generatedAt", generatedAt.toString())
            put("notes", notes)
            put("profileID", profileId)
            put("schemaVersion", currentSchemaVersion)
            put("vehicleName", vehicleName)
        }
        return Json { prettyPrint = true }.encodeToString(kotlinx.serialization.json.JsonObject.serializer(), document)
    }

    companion object {
        const val currentSchemaVersion = 1
    }
}

/** Builds a contribution from the OBD terminal's recent log and the active profile. */
object CommunityContributionBuilder {
    /** Responses are trimmed so a pathological multi-frame reply cannot bloat the document. */
    const val maximumResponseLength = 4_000

    private val failureMarkers = listOf(
        "NO DATA", "ERROR", "UNABLE TO CONNECT", "CAN ERROR", "STOPPED", "BUS INIT", "?",
    )

    fun build(
        logs: List<ObdLogEntry>,
        profile: VehicleProfile,
        vehicleName: String,
        profileId: String,
        appVersion: String = "1.0",
        generatedAt: Instant = Instant.now(),
    ): CommunityPidContribution {
        val entries = mutableMapOf<String, CommunityPidContribution.Entry>()

        for (log in logs) {
            val command = log.sent.trim().uppercase(Locale.US)
            if (command.isEmpty() || isFailureResponse(log.response)) continue
            // Profiles match commands case-sensitively; fall back to the normalized spelling so
            // a hand-typed lowercase command still contributes.
            val decoded = decodedMetrics(profile, log.sent, log.response)
                ?: decodedMetrics(profile, command, log.response)
            if (decoded.isNullOrEmpty()) continue

            val previous = entries[command]
            entries[command] = CommunityPidContribution.Entry(
                command = command,
                response = cleanedResponse(log.response),
                observations = (previous?.observations ?: 0) + 1,
                metrics = decoded,
            )
        }

        return CommunityPidContribution(
            vehicleName = vehicleName,
            profileId = profileId,
            appVersion = appVersion,
            generatedAt = generatedAt,
            notes =
            "Exported from VoltLink's OBD terminal. Values are decoded by the active vehicle " +
                "profile; raw responses are included for verification.",
            entries = entries.values.sortedBy { it.command },
        )
    }

    /** Runs one log entry through the profile and converts every emitted update into a metric. */
    internal fun decodedMetrics(
        profile: VehicleProfile,
        command: String,
        response: String,
    ): List<CommunityPidContribution.Metric>? {
        val updates = profile.parseResponses(command, response)
        if (updates.isEmpty()) return null

        val metrics = mutableMapOf<String, CommunityPidContribution.Metric>()
        for (update in updates) {
            for ((metric, value) in update.contributedMetrics) {
                if (!value.isFinite()) continue
                metrics[metric.displayName] = CommunityPidContribution.Metric(
                    name = metric.displayName,
                    unit = metric.unitSymbol,
                    value = value,
                )
            }
        }
        return metrics.values.sortedBy { it.name }.ifEmpty { null }
    }

    private fun isFailureResponse(raw: String): Boolean {
        val upper = raw.uppercase(Locale.US)
        val trimmed = upper.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("7F")) return true
        return failureMarkers.any { upper.contains(it) }
    }

    private fun cleanedResponse(raw: String): String {
        val cleaned = IsoTp.cleanElmResponse(raw).replace('\n', ' ')
        return cleaned.take(maximumResponseLength)
    }
}

/**
 * Metrics one update contributes to a community decoding document.
 *
 * Multi-value payloads (pack voltage + current + power, three battery temperatures) are all
 * emitted: the point of a contribution is to show what one command revealed. Updates without a
 * [TelemetryMetric] — raw text PIDs, HVAC power, and charge status without a rate — contribute
 * nothing.
 */
val TelemetryUpdate.contributedMetrics: List<Pair<TelemetryMetric, Double>>
    get() = when (this) {
        is TelemetryUpdate.Speed -> listOf(TelemetryMetric.SPEED to kmh)
        is TelemetryUpdate.Power -> listOf(
            TelemetryMetric.POWER to powerKW,
            TelemetryMetric.PACK_VOLTAGE to voltage,
            TelemetryMetric.PACK_CURRENT to current,
        )
        is TelemetryUpdate.PackVoltage -> listOf(TelemetryMetric.PACK_VOLTAGE to volts)
        is TelemetryUpdate.PackCurrent -> listOf(TelemetryMetric.PACK_CURRENT to amps)
        is TelemetryUpdate.Soc -> listOf(TelemetryMetric.SOC to percent)
        is TelemetryUpdate.Soh -> listOf(TelemetryMetric.SOH to percent)
        is TelemetryUpdate.BatteryTemp -> listOf(
            TelemetryMetric.BATTERY_TEMP to avg,
            TelemetryMetric.BATTERY_TEMP_MIN to min,
            TelemetryMetric.BATTERY_TEMP_MAX to max,
        )
        is TelemetryUpdate.Aux12V -> listOf(TelemetryMetric.AUX_12V to volts)
        is TelemetryUpdate.MotorStats -> listOf(
            TelemetryMetric.MOTOR_RPM to rpm,
            TelemetryMetric.MOTOR_TORQUE to torqueNm,
        )
        is TelemetryUpdate.MotorRpm -> listOf(TelemetryMetric.MOTOR_RPM to rpm)
        is TelemetryUpdate.MotorTorque -> listOf(TelemetryMetric.MOTOR_TORQUE to torqueNm)
        is TelemetryUpdate.FuelLevel -> listOf(TelemetryMetric.FUEL_LEVEL to percent)
        is TelemetryUpdate.ThrottlePosition -> listOf(TelemetryMetric.THROTTLE_POSITION to percent)
        is TelemetryUpdate.EngineLoad -> listOf(TelemetryMetric.ENGINE_LOAD to percent)
        is TelemetryUpdate.CoolantTemp -> listOf(TelemetryMetric.COOLANT_TEMP to celsius)
        is TelemetryUpdate.IntakeAirTemp -> listOf(TelemetryMetric.INTAKE_AIR_TEMP to celsius)
        is TelemetryUpdate.AmbientAirTemp -> listOf(TelemetryMetric.AMBIENT_AIR_TEMP to celsius)
        is TelemetryUpdate.Maf -> listOf(TelemetryMetric.MAF to gramsPerSec)
        is TelemetryUpdate.ManifoldPressure -> listOf(TelemetryMetric.MANIFOLD_PRESSURE to kPa)
        is TelemetryUpdate.OilTemp -> listOf(TelemetryMetric.OIL_TEMP to celsius)
        is TelemetryUpdate.TimingAdvance -> listOf(TelemetryMetric.TIMING_ADVANCE to degrees)
        is TelemetryUpdate.BarometricPressure -> listOf(TelemetryMetric.BAROMETRIC_PRESSURE to kPa)
        is TelemetryUpdate.VehicleRange -> listOf(TelemetryMetric.VEHICLE_RANGE to km)
        is TelemetryUpdate.CommunityMetric -> listOf(metric to value)
        is TelemetryUpdate.HvacPower,
        is TelemetryUpdate.ChargingStats,
        is TelemetryUpdate.GenericPid,
        -> emptyList()
    }
