package com.simonkaring.voltlink.core.vehicles

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class VehicleCatalogTest {
    private val catalogJson: String by lazy {
        val candidates = listOf(
            File("src/main/assets/${VehicleCatalog.assetName}"),
            File("app/src/main/assets/${VehicleCatalog.assetName}"),
        )
        candidates.firstOrNull { it.exists() }?.readText()
            ?: error("vehicle_catalog.json not found from ${File(".").absolutePath}")
    }

    @Test
    fun parsesTheShippedDataset() {
        val brands = VehicleCatalog.parse(catalogJson)

        assertTrue("expected the full dataset, got ${brands.size} brands", brands.size > 50)
        val models = brands.flatMap { it.models }
        assertTrue(models.size > 400)

        // Brands and models stay alphabetised so the picker reads like the iOS one.
        assertEquals(brands.map { it.name.lowercase() }, brands.map { it.name.lowercase() }.sorted())
        assertTrue(models.all { it.modelName.isNotBlank() && it.brandName.isNotBlank() })
        assertEquals(models.map { it.id }.distinct().size, models.size)
    }

    @Test
    fun mergesTheHandMaintainedEqaRowsAndGenericEv() {
        val models = VehicleCatalog.parse(catalogJson).flatMap { it.models }

        val eqa = models.first { it.id == "mb-eqa-250" }
        assertEquals(VehicleProfileId.MERCEDES_EQ_A250, eqa.profileId)
        assertEquals(TelemetrySupport.VERIFIED, eqa.telemetrySupport)

        val eqaObd = models.first { it.id == "mb-eqa-250-obdb" }
        assertEquals(VehicleProfileId.MERCEDES_EQ_A_OBDb, eqaObd.profileId)
        assertTrue(eqaObd.hasDedicatedProfile)

        assertNotNull(VehicleCatalog.genericEVModel)
        assertTrue(models.any { it.id == VehicleCatalog.genericEVModel.id })
        assertEquals(1, models.count { it.profileId == VehicleProfileId.MERCEDES_EQ_A250 })
    }

    @Test
    fun mapsDatasetProfilesOntoRunnableProfiles() {
        val models = VehicleCatalog.parse(catalogJson).flatMap { it.models }
        val meb = models.firstOrNull { it.profileId == VehicleProfileId.VOLKSWAGEN_MEB }
        assertNotNull("Volkswagen MEB rows should keep the MEB profile", meb)

        // Community rows with a bundled ABRP document keep a dedicated decoder.
        val aiways = models.first { it.modelName == "U5" }
        assertEquals(VehicleProfileId.AIWAYS_U5, aiways.profileId)
        assertEquals(TelemetrySupport.COMMUNITY, aiways.telemetrySupport)
        assertTrue(aiways.hasDedicatedProfile)

        // The Leaf resolves to the hand-written OVMS decoder.
        val leaf = models.first { it.modelName.contains("leaf", ignoreCase = true) }
        assertEquals(VehicleProfileId.NISSAN_LEAF_ZE1, leaf.profileId)
        assertTrue(leaf.hasDedicatedProfile)

        // Rows with no decoder at all stay on the generic EV profile.
        val generic = models.filter { it.profileId == VehicleProfileId.GENERIC_OBD2 }
        assertTrue(generic.isNotEmpty())

        val genericObd = models.first { it.id == "generic-sae-j1979" }
        assertEquals(VehicleProfileId.GENERIC_OBD2, genericObd.profileId)
    }

    @Test
    fun keepsIceRowsWithNoBattery() {
        val models = VehicleCatalog.parse(catalogJson).flatMap { it.models }
        val ice = models.filter { it.powertrain == Powertrain.ICE }
        assertTrue(ice.isNotEmpty())
        assertTrue(ice.all { it.batteryCapacityKWh >= 0.0 })
        assertTrue(ice.any { it.batteryCapacityKWh == 0.0 })
    }

    @Test
    fun expandsYearLabels() {
        val model = VehicleCatalog.genericEVModel
        fun years(label: String, through: Int = 2027) = model.copy(years = label).modelYears(through)

        assertEquals(listOf(2021), years("2021"))
        assertEquals(listOf(2027, 2026, 2025, 2024, 2023, 2022, 2021, 2020), years("2020+"))
        assertEquals(listOf(2025, 2024), years("2024-2025"))
        assertEquals(listOf(2021), years("2021 · experimental"))
        assertEquals(listOf(2025, 2023), years("2023, 2025"))
        assertEquals(listOf(2025, 2024, 2023), years("2023–2025"))
        assertEquals(emptyList<Int>(), years("TBD"))
        assertEquals(emptyList<Int>(), years("2025-2021"))
    }

    @Test
    fun groupsVariantsIntoFamilies() {
        val models = VehicleCatalog.parse(catalogJson).flatMap { it.models }
        val families = VehicleCatalog.modelFamilies(models)

        assertTrue(families.size < models.size)
        val eqa = families.first { it.id == "mercedes_benz-eqa" }
        assertTrue(eqa.variants.any { it.id == "mb-eqa-250" })
        assertTrue(eqa.modelYears.contains(2021))
        assertEquals(eqa.variantsFor(2021).size, eqa.variants.count { 2021 in it.modelYears() })
    }

    @Test
    fun fallsBackToAMinimalListForMissingData() {
        val brands = VehicleCatalog.parse("")
        assertTrue(brands.isNotEmpty())
        val models = brands.flatMap { it.models }
        assertTrue(models.any { it.id == VehicleCatalog.genericEVModel.id })
        assertTrue(models.any { it.id == "generic-sae-j1979" })
        assertTrue(models.any { it.id == "mb-eqa-250" })
    }
}
