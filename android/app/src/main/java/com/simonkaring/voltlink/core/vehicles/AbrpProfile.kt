package com.simonkaring.voltlink.core.vehicles

import android.content.Context
import com.simonkaring.voltlink.core.obd.IsoTp
import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * One metric definition inside an ABRP (A Better Routeplanner) PID file.
 * `ecu` optionally pins the reading to one responding ECU bucket.
 */
data class AbrpMetricDefinition(
    val equation: String,
    val command: String? = null,
    val ecu: String? = null,
)

/** Models the `iternio/ev-obd-pids` JSON that ABRP itself consumes. */
data class AbrpProfileDefinition(
    val initCommands: List<String> = emptyList(),
    val dataCommands: List<String> = emptyList(),
    val obdProtocol: String? = null,
    val current: AbrpMetricDefinition? = null,
    val voltage: AbrpMetricDefinition? = null,
    val soc: AbrpMetricDefinition? = null,
    val soh: AbrpMetricDefinition? = null,
    val battTemp: AbrpMetricDefinition? = null,
    val extTemp: AbrpMetricDefinition? = null,
    val speed: AbrpMetricDefinition? = null,
    val isCharging: AbrpMetricDefinition? = null,
)

/** Reads an ABRP document; both key spellings the community catalogs use are accepted. */
object AbrpDefinitionParser {
    fun parse(text: String): AbrpProfileDefinition? {
        val root = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null

        fun commands(vararg keys: String): List<String> {
            for (key in keys) {
                val list = (root[key] as? JsonObject)?.get("command") as? JsonArray ?: continue
                return list.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
            }
            return emptyList()
        }

        fun metric(key: String): AbrpMetricDefinition? {
            val objectValue = root[key] as? JsonObject ?: return null
            val equation = (objectValue["equation"] as? JsonPrimitive)?.contentOrNull
                ?.takeIf { it.isNotBlank() } ?: return null
            return AbrpMetricDefinition(
                equation = equation,
                command = (objectValue["command"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() },
                ecu = (objectValue["ecu"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() },
            )
        }

        return AbrpProfileDefinition(
            initCommands = commands("init_commands", "Init_Commands"),
            dataCommands = commands("data_commands", "Data_Commands"),
            obdProtocol = (root["obd_protocol"] as? JsonPrimitive)?.contentOrNull,
            current = metric("current"),
            voltage = metric("voltage"),
            soc = metric("soc"),
            soh = metric("soh"),
            battTemp = metric("batt_temp"),
            extTemp = metric("ext_temp"),
            speed = metric("speed"),
            isCharging = metric("is_charging"),
        )
    }
}

/**
 * Generic EV profile that runs a community ABRP definition instead of hand-written decoders.
 *
 * Parity notes with the iOS `ABRPGenericVehicleProfile`: responses are reassembled through
 * ISO-TP before the equation reads bytes, commands match exactly (no prefix matching, or DIDs
 * sharing a prefix would cross-assign), and every definition whose `command` matches is
 * evaluated so one reply can publish current, voltage and charging status together.
 */
class AbrpGenericProfile(
    override val vehicleName: String,
    override val batteryUsableCapacityKWh: Double,
    val definition: AbrpProfileDefinition,
) : VehicleProfile {
    override val isElectricVehicle: Boolean = true

    override val initializationCommands: List<String>
        get() = definition.initCommands.ifEmpty {
            val protocol = definition.obdProtocol ?: "6"
            listOf("AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT ST FF", "AT SP $protocol")
        }

    override val pollingCommands: List<String> get() = definition.dataCommands

    override val supportedMetrics: Set<TelemetryMetric> = buildSet {
        if (definition.soc != null) add(TelemetryMetric.SOC)
        if (definition.voltage != null) add(TelemetryMetric.PACK_VOLTAGE)
        if (definition.current != null) add(TelemetryMetric.PACK_CURRENT)
        if (definition.voltage != null && definition.current != null) add(TelemetryMetric.POWER)
        if (definition.soh != null) add(TelemetryMetric.SOH)
        if (definition.battTemp != null) add(TelemetryMetric.BATTERY_TEMP)
        if (definition.speed != null) add(TelemetryMetric.SPEED)
        if (definition.extTemp != null) add(TelemetryMetric.AMBIENT_AIR_TEMP)
        // `is_charging` feeds the charging state through `.chargingStats` only; it has no
        // dashboard tile of its own, so it is not advertised as a supported metric.
    }

    override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? =
        parseResponses(command, rawResponse).firstOrNull()

    override fun parseResponses(command: String, rawResponse: String): List<TelemetryUpdate> {
        val buckets = IsoTp.assemblePayloads(rawResponse)
        if (buckets.isEmpty()) return emptyList()
        val concatenated = buckets.joinToString("") { it.payload }

        fun bytesFor(definition: AbrpMetricDefinition): ByteArray {
            val ecu = definition.ecu?.uppercase()?.takeIf { it.isNotEmpty() }
            val hex = ecu?.let { wanted ->
                buckets.firstOrNull {
                    val key = it.ecu.uppercase()
                    key == wanted || key.endsWith(wanted)
                }?.payload
            } ?: concatenated
            return extractBytes(hex, command)
        }

        val updates = mutableListOf<TelemetryUpdate>()

        definition.soc?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    updates += TelemetryUpdate.Soc(it.coerceIn(0.0, 100.0))
                }
            }
        }

        definition.voltage?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    updates += TelemetryUpdate.PackVoltage(it)
                }
            }
        }

        definition.current?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    // Standalone current; the manager multiplies it by the last measured pack
                    // voltage rather than a fabricated nominal one.
                    updates += TelemetryUpdate.PackCurrent(it)
                }
            }
        }

        definition.soh?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    updates += TelemetryUpdate.Soh(it.coerceIn(0.0, 100.0))
                }
            }
        }

        definition.battTemp?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    updates += TelemetryUpdate.BatteryTemp(min = it, max = it, avg = it)
                }
            }
        }

        definition.speed?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    updates += TelemetryUpdate.Speed(it.coerceAtLeast(0.0))
                }
            }
        }

        definition.extTemp?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    updates += TelemetryUpdate.AmbientAirTemp(it)
                }
            }
        }

        definition.isCharging?.takeIf { matchesCommand(it.command, command) }?.let { definition ->
            val bytes = bytesFor(definition)
            if (bytes.isNotEmpty()) {
                AbrpExpression.evaluate(definition.equation, bytes)?.let {
                    if (it > 0.5) updates += TelemetryUpdate.ChargingStats(kwRate = null, acOrDc = "")
                }
            }
        }

        return updates
    }

    /** Exact match only — DIDs that share a prefix must not cross-assign metrics. */
    private fun matchesCommand(target: String?, command: String): Boolean {
        val wanted = target?.replace(" ", "")?.uppercase()?.takeIf { it.isNotEmpty() } ?: return false
        return wanted == command.replace(" ", "").uppercase()
    }

    /** Strips the UDS positive-response echo (`62 <DID>`) and returns the remaining bytes. */
    private fun extractBytes(hex: String, command: String): ByteArray {
        var clean = hex.uppercase()
        val compact = command.replace(" ", "").uppercase()
        if (compact.startsWith("22") && compact.length >= 6) {
            val marker = "62" + compact.substring(2, 6)
            val index = clean.indexOf(marker)
            if (index >= 0) clean = clean.substring(index + marker.length)
        }
        return IsoTp.hexBytes(clean)
    }
}

/**
 * Bundled ABRP definitions and the lookup used by [VehicleProfileId].
 *
 * The JSON files ship as assets, so the loader needs a reader; the application installs one
 * from its `AssetManager` on startup. Without a reader (JVM tests, early callers) the profiles
 * simply report no definition and the registry falls back to the generic EV decoder.
 */
object AbrpProfileLoader {
    /** One bundled profile: asset file, display name and usable pack capacity. */
    data class Spec(val filename: String, val name: String, val capacityKWh: Double)

    /** Reads one asset by its path relative to the assets root. */
    fun interface AssetReader {
        fun read(path: String): String?
    }

    private const val directory = "abrp_pids"

    private var reader: AssetReader? = null
    private val cache = mutableMapOf<String, AbrpProfileDefinition?>()

    val specs: List<Spec> = listOf(
        Spec("ford_MachE.json", "Ford Mustang Mach-E", 91.0),
        Spec("hkmc_Ioniq5.json", "Hyundai/Kia E-GMP (IONIQ 5 / EV6)", 77.4),
        Spec("hkmc_hkmc2019.json", "Hyundai / Kia (Kona / Niro EV)", 64.0),
        Spec("hkmc_hkmc2017.json", "Hyundai / Kia (IONIQ Electric / Soul EV 2017)", 28.0),
        Spec("volkswagen_MEB.json", "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)", 77.0),
        Spec("volkswagen_eGolf.json", "Volkswagen e-Golf (ABRP)", 35.8),
        Spec("volkswagen_eUP.json", "Volkswagen e-Up! (ABRP)", 32.3),
        Spec("Mini_MiniCooperSE.json", "Mini Cooper SE (ABRP)", 28.9),
        Spec("renault_zoe2.json", "Renault Zoe ZE50 (ABRP)", 52.0),
        Spec("renault_zoe.json", "Renault Zoe ZE40 (ABRP)", 41.0),
        Spec("mg_mgzsev.json", "MG ZS EV (ABRP)", 68.3),
        Spec("jaguar_ipace2021.json", "Jaguar I-Pace 2021+ (ABRP)", 84.7),
        Spec("jaguar_ipace2019.json", "Jaguar I-Pace 2019 (ABRP)", 84.7),
        Spec("gmc_bolt19.json", "Chevrolet Bolt EV 2019+ (ABRP)", 66.0),
        Spec("gmc_bolt17.json", "Chevrolet Bolt EV 2017 (ABRP)", 60.0),
        Spec("honda_eny1.json", "Honda e:Ny1 (ABRP)", 68.8),
        Spec("aiways_u5.json", "Aiways U5 (ABRP)", 63.0),
        Spec("byd_atto3.json", "BYD Atto 3 / Yuan Plus (ABRP)", 60.5),
        Spec("bmw_i3.json", "BMW i3 (ABRP)", 37.9),
        Spec("deepal_s05.json", "Deepal S05 (ABRP)", 56.1),
    )

    fun install(assetReader: AssetReader) {
        reader = assetReader
        cache.clear()
    }

    fun install(context: Context) {
        val assets = context.applicationContext.assets
        install { path ->
            runCatching { assets.open(path).bufferedReader().use { it.readText() } }.getOrNull()
        }
    }

    /** Parsed definition for one bundled file, or null when the asset is unavailable. */
    fun definition(filename: String): AbrpProfileDefinition? {
        if (cache.containsKey(filename)) return cache[filename]
        val text = reader?.read("$directory/$filename")
        val parsed = text?.let { AbrpDefinitionParser.parse(it) }
        cache[filename] = parsed
        return parsed
    }

    fun load(filename: String, name: String, capacityKWh: Double): VehicleProfile? =
        definition(filename)?.let { AbrpGenericProfile(name, capacityKWh, it) }

    fun load(spec: Spec): VehicleProfile? = load(spec.filename, spec.name, spec.capacityKWh)

    /** Bundled profile by file name, using the display name and capacity from [specs]. */
    fun load(filename: String): VehicleProfile? = specs.firstOrNull { it.filename == filename }?.let { load(it) }

    /** Every bundled profile that could be read; used by the PID picker and the tests. */
    fun bundledProfiles(): List<VehicleProfile> = specs.mapNotNull { load(it) }
}
