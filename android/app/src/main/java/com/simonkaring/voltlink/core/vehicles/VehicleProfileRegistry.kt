package com.simonkaring.voltlink.core.vehicles

/**
 * Stable identity for a registered profile, mirroring the iOS `VehicleProfileID` enum.
 *
 * Profiles whose decoding comes from a community ABRP PID file carry that file's name and are
 * resolved through [AbrpProfileLoader]; the hand-written profiles stay compiled in.
 */
enum class VehicleProfileId(val displayName: String, private val abrpFilename: String? = null) {
    MERCEDES_EQ_A250("Mercedes-Benz EQA 250 (2021)"),
    MERCEDES_EQ_A_OBDb("Mercedes-Benz EQA 250 (OBDb community)"),
    VOLKSWAGEN_MEB("Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)"),
    HYUNDAI_KIA_EGMP("Hyundai/Kia E-GMP (IONIQ 5 / EV6)"),
    HYUNDAI_KIA_2019("Hyundai / Kia (Kona / Niro EV)", "hkmc_hkmc2019.json"),
    HYUNDAI_KIA_2017("Hyundai / Kia (IONIQ Electric / Soul EV 2017)", "hkmc_hkmc2017.json"),
    VOLKSWAGEN_E_GOLF("Volkswagen e-Golf (ABRP)", "volkswagen_eGolf.json"),
    VOLKSWAGEN_E_UP("Volkswagen e-Up! (ABRP)", "volkswagen_eUP.json"),
    FORD_MACH_E("Ford Mustang Mach-E (ABRP)", "ford_MachE.json"),
    MINI_COOPER_SE("Mini Cooper SE (ABRP)", "Mini_MiniCooperSE.json"),
    RENAULT_ZOE_ZE50("Renault Zoe ZE50 (ABRP)", "renault_zoe2.json"),
    RENAULT_ZOE_ZE40("Renault Zoe ZE40 (ABRP)", "renault_zoe.json"),
    MG_ZS_EV("MG ZS EV (ABRP)", "mg_mgzsev.json"),
    JAGUAR_I_PACE("Jaguar I-Pace 2021+ (ABRP)", "jaguar_ipace2021.json"),
    JAGUAR_I_PACE_2019("Jaguar I-Pace 2019 (ABRP)", "jaguar_ipace2019.json"),
    CHEVROLET_BOLT("Chevrolet Bolt EV 2019+ (ABRP)", "gmc_bolt19.json"),
    CHEVROLET_BOLT_2017("Chevrolet Bolt EV 2017 (ABRP)", "gmc_bolt17.json"),
    HONDA_E_NY1("Honda e:Ny1 (ABRP)", "honda_eny1.json"),
    NISSAN_LEAF_ZE1("Nissan Leaf 62 kWh (OVMS)"),
    AIWAYS_U5("Aiways U5 (ABRP)", "aiways_u5.json"),
    BYD_ATTO3("BYD Atto 3 / Yuan Plus (ABRP)", "byd_atto3.json"),
    BMW_I3("BMW i3 (ABRP)", "bmw_i3.json"),
    DEEPAL_S05("Deepal S05 (ABRP)", "deepal_s05.json"),
    GENERIC_OBD2("Generic SAE J1979 OBD-II"),
    GENERIC_EV("Generic EV (SAE J1979)"),
    ;

    /** True when the decoding comes from a bundled community PID document. */
    val isCommunityProfile: Boolean get() = abrpFilename != null

    /**
     * Builds the profile. An ABRP profile whose asset cannot be read falls back to the generic
     * EV decoder instead of failing the selection, exactly like the iOS registry.
     */
    fun makeProfile(): VehicleProfile = when (this) {
        MERCEDES_EQ_A250 -> MercedesEqa250Profile()
        MERCEDES_EQ_A_OBDb -> MercedesEqaObdbProfile()
        VOLKSWAGEN_MEB -> VolkswagenMebProfile()
        HYUNDAI_KIA_EGMP -> HyundaiKiaEgmpProfile()
        NISSAN_LEAF_ZE1 -> NissanLeafZe1Profile()
        GENERIC_OBD2 -> GenericObd2Profile()
        GENERIC_EV -> GenericEvProfile()
        else -> abrpFilename?.let { AbrpProfileLoader.load(it) } ?: GenericEvProfile()
    }
}
