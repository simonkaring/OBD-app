package com.simonkaring.voltlink.core.vehicles

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Search behaviour behind the catalog picker's single search field. */
class VehicleCatalogQueryTest {
    private val eqa = VehicleModelEntry(
        id = "mb-eqa-250",
        brandName = "Mercedes-Benz",
        modelName = "EQA 250",
        years = "2021",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 66.5,
        profileId = VehicleProfileId.MERCEDES_EQ_A250,
        telemetrySupport = TelemetrySupport.VERIFIED,
        modelFamilyId = "mercedes_benz-eqa",
        modelFamilyName = "EQA",
        variantDisplayName = "EQA 250 · 2021",
    )

    private val meb = VehicleModelEntry(
        id = "vw-id3-2020",
        brandName = "Volkswagen",
        modelName = "ID.3",
        years = "2020-2023",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 58.0,
        profileId = VehicleProfileId.VOLKSWAGEN_MEB,
        modelFamilyId = "volkswagen-id3",
        modelFamilyName = "ID.3",
    )

    private val leaf = VehicleModelEntry(
        id = "nissan-leaf-ze1",
        brandName = "Nissan",
        modelName = "Leaf",
        years = "2019+",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 62.0,
        profileId = VehicleProfileId.NISSAN_LEAF_ZE1,
        modelFamilyId = "nissan-leaf",
        modelFamilyName = "Leaf",
    )

    private val golf = VehicleModelEntry(
        id = "vw-e-golf",
        brandName = "Volkswagen",
        modelName = "e-Golf",
        years = "2017 · experimental",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 35.8,
        profileId = VehicleProfileId.VOLKSWAGEN_E_GOLF,
    )

    @Test
    fun matchesBrandModelFamilyAndVariant() {
        assertTrue(eqa.matchesCatalogQuery("mercedes"))
        assertTrue(eqa.matchesCatalogQuery("EQA"))
        assertTrue(eqa.matchesCatalogQuery("eqa 250"))
        assertTrue(eqa.matchesCatalogQuery("EQA 250 · 2021"))
        assertTrue(leaf.matchesCatalogQuery("leaf"))
    }

    @Test
    fun matchesAYearInsideARangeInsteadOfOnlyTheLabel() {
        // The label reads "2020-2023"; a customer searches their own model year.
        assertTrue(meb.matchesCatalogQuery("2022"))
        assertTrue(meb.matchesCatalogQuery("2020"))
        // Open-ended ranges include the current and next model year.
        assertTrue(leaf.matchesCatalogQuery("2021"))
        // A year the range does not cover stays out.
        assertFalse(meb.matchesCatalogQuery("2019"))
    }

    @Test
    fun matchesTheYearsLabelVerbatimWhenItCarriesAQualification() {
        // "2017 · experimental" is not a parseable range, so only the literal text matches.
        assertTrue(golf.matchesCatalogQuery("2017"))
        assertFalse(golf.matchesCatalogQuery("2018"))
    }

    @Test
    fun rejectsUnrelatedQueries() {
        assertFalse(eqa.matchesCatalogQuery("taycan"))
        assertFalse(eqa.matchesCatalogQuery("2024"))
        assertTrue(eqa.matchesCatalogQuery("  "))
    }
}
