package com.simonkaring.voltlink.core.vehicles

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.util.Locale

/** Drivetrain of a catalog row; the raw values are the dataset's labels. */
enum class Powertrain(val label: String) {
    EV("Electric (BEV)"),
    PHEV("Plug-in Hybrid (PHEV)"),
    ICE("Gasoline / Diesel (ICE)"),
    ;

    companion object {
        fun from(raw: String?): Powertrain? = entries.firstOrNull { it.label == raw }
    }
}

/** Describes the best telemetry path the dataset claims for a row. */
enum class TelemetrySupport(val label: String) {
    VERIFIED("Verified live telemetry"),
    COMMUNITY("Community live telemetry"),
    GENERIC("Generic OBD telemetry"),
    ;

    companion object {
        fun from(raw: String?): TelemetrySupport =
            when (raw?.lowercase(Locale.US)) {
                "verified" -> VERIFIED
                "community" -> COMMUNITY
                else -> GENERIC
            }
    }
}

/**
 * One row of the catalog. Static specifications are always shown; live values still depend
 * on the car and on the profile the app actually runs — [profileId] is the Android profile
 * the row maps to, which falls back to a generic decoder for brands without one.
 */
data class VehicleModelEntry(
    val id: String,
    val brandName: String,
    val modelName: String,
    val years: String,
    val powertrain: Powertrain,
    val batteryCapacityKWh: Double,
    val profileId: VehicleProfileId,
    val telemetrySupport: TelemetrySupport = TelemetrySupport.GENERIC,
    val estimatedRangeKm: Double? = null,
    val notes: String? = null,
    val modelFamilyId: String? = null,
    val modelFamilyName: String? = null,
    val variantDisplayName: String? = null,
) {
    val fullName: String get() = "$brandName $modelName"

    val resolvedVariantDisplayName: String get() = variantDisplayName ?: modelName

    /** True when this app has a dedicated decoder for the row instead of the generic fallback. */
    val hasDedicatedProfile: Boolean
        get() = profileId != VehicleProfileId.GENERIC_EV && profileId != VehicleProfileId.GENERIC_OBD2

    /**
     * Expand the catalog's year labels, preserving gaps such as "2023, 2025".
     * Open-ended entries include the next model year; closed ranges stay exact.
     */
    fun modelYears(through: Int = LocalDate.now().year + 1): List<Int> {
        val result = sortedSetOf<Int>()
        // Hand-maintained entries may append a qualification, e.g. "2021 · experimental".
        for (segment in years.substringBefore('·').split(',')) {
            val label = segment.filterNot { it.isWhitespace() }.replace('–', '-')
            if (!YEAR_LABEL.matches(label)) return emptyList()
            val first = label.take(4).toInt()
            val last = if (label.endsWith("+")) maxOf(first, through) else label.takeLast(4).toInt()
            if (first > last || last > 9999) return emptyList()
            result.addAll(first..last)
        }
        return result.sortedDescending()
    }

    /**
     * Matches a free-text query against the fields the picker advertises: brand, model family,
     * model, variant name and model year. Year labels are ranges ("2020-2023", "2019+"), so a
     * bare year is matched through the expanded year list rather than as a substring.
     */
    fun matchesCatalogQuery(query: String): Boolean {
        val wanted = query.trim()
        if (wanted.isEmpty()) return true
        if (brandName.contains(wanted, ignoreCase = true)) return true
        if (modelName.contains(wanted, ignoreCase = true)) return true
        if (resolvedVariantDisplayName.contains(wanted, ignoreCase = true)) return true
        if (!modelFamilyName.isNullOrBlank() && modelFamilyName.contains(wanted, ignoreCase = true)) return true
        if (years.contains(wanted, ignoreCase = true)) return true
        val year = wanted.toIntOrNull() ?: return false
        return year in modelYears()
    }

    private companion object {
        val YEAR_LABEL = Regex("^[0-9]{4}(-[0-9]{4}|\\+)?$")
    }
}

data class VehicleModelFamily(
    val id: String,
    val name: String,
    val variants: List<VehicleModelEntry>,
) {
    val modelYears: List<Int>
        get() = variants.flatMap { it.modelYears() }.toSortedSet().sortedDescending()

    fun variantsFor(year: Int): List<VehicleModelEntry> = variants.filter { year in it.modelYears() }
}

data class VehicleBrand(
    val id: String,
    val name: String,
    val models: List<VehicleModelEntry>,
) {
    val modelFamilies: List<VehicleModelFamily> get() = VehicleCatalog.modelFamilies(models)
}

/**
 * The OpenEV / Iternio derived model list shown by the vehicle picker.
 *
 * The JSON ships as an asset and is parsed once; [parse] is pure so the JVM tests can run it
 * against the real asset file without an Android runtime.
 */
object VehicleCatalog {
    const val assetName = "vehicle_catalog.json"
    const val dataSource = "OpenEV Data Dataset & Iternio EV-OBD-PIDs"

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    val defaultModel = VehicleModelEntry(
        id = "mb-eqa-250",
        brandName = "Mercedes-Benz",
        modelName = "EQA 250",
        years = "2021",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 66.5,
        profileId = VehicleProfileId.MERCEDES_EQ_A250,
        telemetrySupport = TelemetrySupport.VERIFIED,
        estimatedRangeKm = 426.0,
        notes =
        "Pack-voltage decoding only. SOC and SOC-derived charging are unavailable; DID 0x0210 " +
            "is retained for raw capture pending validation.",
        modelFamilyId = "mercedes_benz-eqa",
        modelFamilyName = "EQA",
        variantDisplayName = "EQA 250 · 2021",
    )

    val eqaOBDbModel = VehicleModelEntry(
        id = "mb-eqa-250-obdb",
        brandName = "Mercedes-Benz",
        modelName = "EQA 250 (OBDb community)",
        years = "2021 · experimental",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 66.5,
        profileId = VehicleProfileId.MERCEDES_EQ_A_OBDb,
        telemetrySupport = TelemetrySupport.COMMUNITY,
        estimatedRangeKm = 426.0,
        notes =
        "Experimental OBDb requests. SOC, voltage, current, wheel speed, 12 V and HV coolant " +
            "temperature. Validate readings and current direction on your car; coolant is not " +
            "cell temperature.",
        modelFamilyId = "mercedes_benz-eqa",
        modelFamilyName = "EQA",
        variantDisplayName = "EQA 250 · OBDb community (experimental)",
    )

    val genericEVModel = VehicleModelEntry(
        id = "generic-ev-can",
        brandName = "Generic",
        modelName = "EV / Vehicle Not Listed",
        years = "2015+",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 0.0,
        profileId = VehicleProfileId.GENERIC_EV,
        telemetrySupport = TelemetrySupport.GENERIC,
        notes =
        "Standard OBD readings only, where available. Battery SOC, power and charging telemetry " +
            "are not guaranteed. Battery capacity and range are unknown.",
        modelFamilyId = "generic-ev",
        modelFamilyName = "Generic EV",
    )

    /** All models of the checked-in dataset, with the hand-maintained EQA rows merged in. */
    val brands: List<VehicleBrand> by lazy { load(null) }

    val allModels: List<VehicleModelEntry> get() = brands.flatMap { it.models }

    fun load(context: Context?): List<VehicleBrand> {
        val text = context?.let { ctx ->
            runCatching { ctx.assets.open(assetName).bufferedReader().use { it.readText() } }.getOrNull()
        }
        return parse(text ?: "")
    }

    fun modelFor(id: String?, models: List<VehicleModelEntry> = allModels): VehicleModelEntry? =
        id?.let { wanted -> models.firstOrNull { it.id == wanted } }

    /** Parses the catalog JSON. A blank or malformed document yields the minimal fallback. */
    fun parse(jsonText: String): List<VehicleBrand> {
        val container = runCatching { json.decodeFromString<CatalogContainer>(jsonText) }.getOrNull()
        val parsed = container?.brands?.mapNotNull { brand ->
            val models = brand.models.mapNotNull { dto -> dto.toEntry(brand) }
                .filter { model ->
                    // A zero pack size means a bad dataset row for a BEV/PHEV, but is correct
                    // for an ICE entry — don't let the sanity check eat those.
                    (model.batteryCapacityKWh > 0 || model.powertrain == Powertrain.ICE ||
                        model.id == genericEVModel.id) &&
                        (model.profileId != VehicleProfileId.MERCEDES_EQ_A250 || model.id == defaultModel.id)
                }
                .sortedBy { it.modelName.lowercase(Locale.US) }
            if (models.isEmpty()) null else VehicleBrand(brand.id, brand.name, models)
        }
        if (parsed.isNullOrEmpty()) return fallbackBrands

        val withDefaults = parsed.map { brand ->
            if (brand.name != defaultModel.brandName) {
                brand
            } else {
                val additions = listOf(defaultModel, eqaOBDbModel).filter { model ->
                    brand.models.none { it.id == model.id }
                }
                brand.copy(
                    models = (additions + brand.models).sortedBy { it.modelName.lowercase(Locale.US) },
                )
            }
        }.toMutableList()

        if (withDefaults.none { brand -> brand.models.any { it.id == genericEVModel.id } }) {
            withDefaults += VehicleBrand("generic-ev-fallback", "Generic EV", listOf(genericEVModel))
        }
        return withDefaults.sortedBy { it.name.lowercase(Locale.US) }
    }

    /** Groups variants that share an explicit family, or identical display metadata for legacy rows. */
    fun modelFamilies(models: List<VehicleModelEntry>): List<VehicleModelFamily> {
        data class FamilyKey(val explicitId: String?, val legacyName: String?)

        val grouped = models.groupBy { model ->
            val familyId = model.modelFamilyId
            if (!familyId.isNullOrEmpty()) {
                FamilyKey(familyId, null)
            } else {
                FamilyKey(null, (model.modelFamilyName ?: model.modelName).lowercase(Locale.US))
            }
        }
        return grouped.values.map { variants ->
            val sorted = variants.sortedWith(
                compareBy({ it.resolvedVariantDisplayName.lowercase(Locale.US) }, { it.id }),
            )
            val first = sorted.first()
            VehicleModelFamily(
                id = first.modelFamilyId ?: "legacy:${sorted.minOf { it.id }}",
                name = first.modelFamilyName ?: first.modelName,
                variants = sorted,
            )
        }.sortedWith(compareBy({ it.name.lowercase(Locale.US) }, { it.id }))
    }

    private val fallbackBrands: List<VehicleBrand> = listOf(
        VehicleBrand(
            id = "generic",
            name = "Generic OBD-II & Others",
            models = listOf(
                genericEVModel,
                VehicleModelEntry(
                    id = "generic-sae-j1979",
                    brandName = "Generic",
                    modelName = "Standard SAE J1979 (Gas / Hybrid)",
                    years = "1996+",
                    powertrain = Powertrain.ICE,
                    batteryCapacityKWh = 0.0,
                    profileId = VehicleProfileId.GENERIC_OBD2,
                ),
            ),
        ),
        VehicleBrand(
            id = "mercedes",
            name = "Mercedes-Benz",
            models = listOf(defaultModel, eqaOBDbModel),
        ),
    ).sortedBy { it.name.lowercase(Locale.US) }

    /**
     * Maps a dataset profile identifier onto the profile this app can actually run.
     *
     * The community identifiers are the ABRP file names, so they resolve to the bundled
     * definitions; `nissan_leaf` resolves to the hand-written OVMS decoder.
     */
    fun profileFor(rawProfileId: String?): VehicleProfileId =
        when (rawProfileId) {
            "mercedesEQA250" -> VehicleProfileId.MERCEDES_EQ_A250
            "mercedesEQAOBDb" -> VehicleProfileId.MERCEDES_EQ_A_OBDb
            "hkmc_Ioniq5" -> VehicleProfileId.HYUNDAI_KIA_EGMP
            "hkmc_hkmc2019" -> VehicleProfileId.HYUNDAI_KIA_2019
            "hkmc_hkmc2017" -> VehicleProfileId.HYUNDAI_KIA_2017
            "volkswagen_MEB" -> VehicleProfileId.VOLKSWAGEN_MEB
            "volkswagen_eGolf" -> VehicleProfileId.VOLKSWAGEN_E_GOLF
            "volkswagen_eUP" -> VehicleProfileId.VOLKSWAGEN_E_UP
            "ford_MachE" -> VehicleProfileId.FORD_MACH_E
            "Mini_MiniCooperSE" -> VehicleProfileId.MINI_COOPER_SE
            "renault_zoe2" -> VehicleProfileId.RENAULT_ZOE_ZE50
            "renault_zoe" -> VehicleProfileId.RENAULT_ZOE_ZE40
            "mg_mgzsev" -> VehicleProfileId.MG_ZS_EV
            "jaguar_ipace2021" -> VehicleProfileId.JAGUAR_I_PACE
            "jaguar_ipace2019" -> VehicleProfileId.JAGUAR_I_PACE_2019
            "gmc_bolt19" -> VehicleProfileId.CHEVROLET_BOLT
            "gmc_bolt17" -> VehicleProfileId.CHEVROLET_BOLT_2017
            "honda_eny1" -> VehicleProfileId.HONDA_E_NY1
            "nissan_leaf" -> VehicleProfileId.NISSAN_LEAF_ZE1
            "aiways_u5" -> VehicleProfileId.AIWAYS_U5
            "byd_atto3" -> VehicleProfileId.BYD_ATTO3
            "bmw_i3" -> VehicleProfileId.BMW_I3
            "deepal_s05" -> VehicleProfileId.DEEPAL_S05
            "genericOBD2" -> VehicleProfileId.GENERIC_OBD2
            else -> VehicleProfileId.GENERIC_EV
        }

    private fun ModelDto.toEntry(brand: BrandDto): VehicleModelEntry? {
        val name = modelName?.takeIf { it.isNotBlank() } ?: return null
        val train = Powertrain.from(powertrain) ?: return null
        return VehicleModelEntry(
            id = id,
            brandName = brandName?.takeIf { it.isNotBlank() } ?: brand.name,
            modelName = name,
            years = years.orEmpty(),
            powertrain = train,
            batteryCapacityKWh = batteryCapacityKWh ?: 0.0,
            profileId = profileFor(profileID),
            telemetrySupport = TelemetrySupport.from(telemetrySupport),
            estimatedRangeKm = estimatedRangeKm,
            notes = notes,
            modelFamilyId = modelFamilyID,
            modelFamilyName = modelFamilyName,
            variantDisplayName = variantDisplayName,
        )
    }

    @Serializable
    private data class CatalogContainer(val brands: List<BrandDto> = emptyList())

    @Serializable
    private data class BrandDto(
        val id: String = "",
        val name: String = "",
        @SerialName("iconSymbol") val iconSymbol: String = "car.fill",
        val models: List<ModelDto> = emptyList(),
    )

    @Serializable
    private data class ModelDto(
        val id: String = "",
        val brandName: String? = null,
        val modelName: String? = null,
        val years: String? = null,
        val powertrain: String? = null,
        val batteryCapacityKWh: Double? = null,
        @SerialName("profileID") val profileID: String? = null,
        val telemetrySupport: String? = null,
        val estimatedRangeKm: Double? = null,
        val notes: String? = null,
        @SerialName("modelFamilyID") val modelFamilyID: String? = null,
        val modelFamilyName: String? = null,
        val variantDisplayName: String? = null,
    )
}
