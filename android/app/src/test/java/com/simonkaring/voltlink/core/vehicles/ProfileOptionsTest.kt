package com.simonkaring.voltlink.core.vehicles

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfileOptionsTest {
    private fun entry(
        id: String,
        profileId: VehicleProfileId,
        familyId: String?,
        variant: String,
    ) = VehicleModelEntry(
        id = id,
        brandName = "Mercedes-Benz",
        modelName = "EQA 250",
        years = "2021",
        powertrain = Powertrain.EV,
        batteryCapacityKWh = 66.5,
        profileId = profileId,
        modelFamilyId = familyId,
        modelFamilyName = familyId?.let { "EQA" },
        variantDisplayName = variant,
    )

    private val verified =
        entry("mb-eqa-250", VehicleProfileId.MERCEDES_EQ_A250, "mercedes_benz-eqa", "EQA 250 · 2021")
    private val community = entry(
        "mb-eqa-250-obdb",
        VehicleProfileId.MERCEDES_EQ_A_OBDb,
        "mercedes_benz-eqa",
        "EQA 250 · OBDb community (experimental)",
    )
    private val otherFamily =
        entry("mb-eqb", VehicleProfileId.MERCEDES_EQ_A250, "mercedes_benz-eqb", "EQB 250")

    @Test
    fun `both eqa decoders are offered for the picked row`() {
        val options = VehicleCatalog.profileOptions(
            listOf(otherFamily, community, verified),
            "mb-eqa-250",
            VehicleProfileId.MERCEDES_EQ_A250,
        )

        assertEquals(
            listOf(VehicleProfileId.MERCEDES_EQ_A250, VehicleProfileId.MERCEDES_EQ_A_OBDb),
            options.map { it.profileId },
        )
    }

    @Test
    fun `the stored profile anchors the comparison when no row was picked`() {
        val options = VehicleCatalog.profileOptions(
            listOf(otherFamily, verified, community),
            null,
            VehicleProfileId.MERCEDES_EQ_A_OBDb,
        )

        assertEquals(2, options.size)
        assertEquals(
            setOf(VehicleProfileId.MERCEDES_EQ_A250, VehicleProfileId.MERCEDES_EQ_A_OBDb),
            options.map { it.profileId }.toSet(),
        )
    }

    @Test
    fun `abrp tables are offered next to the compiled-in decoder`() {
        assertEquals(
            listOf(VehicleProfileId.VOLKSWAGEN_MEB_ABRP),
            VehicleCatalog.profileAlternatives(VehicleProfileId.VOLKSWAGEN_MEB),
        )
        assertEquals(
            listOf(VehicleProfileId.HYUNDAI_KIA_EGMP),
            VehicleCatalog.profileAlternatives(VehicleProfileId.HYUNDAI_KIA_EGMP_ABRP),
        )
        assertEquals(
            listOf(VehicleProfileId.HYUNDAI_KIA_EGMP_ABRP),
            VehicleCatalog.profileAlternatives(VehicleProfileId.HYUNDAI_KIA_EGMP),
        )
        assertTrue(VehicleCatalog.profileAlternatives(VehicleProfileId.BMW_I3).isEmpty())
    }

    @Test
    fun `a single decoder and a family-less row offer nothing to compare`() {
        val single = VehicleCatalog.profileOptions(
            listOf(otherFamily),
            "mb-eqb",
            VehicleProfileId.MERCEDES_EQ_A250,
        )
        val familyLess = VehicleCatalog.profileOptions(
            listOf(entry("lonely", VehicleProfileId.GENERIC_EV, null, "Generic EV")),
            "lonely",
            VehicleProfileId.GENERIC_EV,
        )

        assertEquals(1, single.size)
        assertTrue(familyLess.isEmpty())
    }
}
