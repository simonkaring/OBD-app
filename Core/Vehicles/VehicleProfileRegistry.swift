import Foundation

/// Identifies a registered `VehicleProfile` by a stable, `Codable`/`Hashable` value —
/// needed since `VehicleProfile` is a protocol (existential) and can't back a `Picker` selection directly.
public enum VehicleProfileID: String, CaseIterable, Identifiable, Codable, Sendable {
    case mercedesEQA250
    case hyundaiKiaEGMP
    case hkmcIoniq5 = "hkmc_Ioniq5"
    case hkmc2019 = "hkmc_hkmc2019"
    case hkmc2017 = "hkmc_hkmc2017"
    case volkswagenMEB
    case volkswagenMEBABRP = "volkswagen_MEB"
    case volkswagenEGolf = "volkswagen_eGolf"
    case volkswagenEUp = "volkswagen_eUP"
    case genericOBD2
    case genericEV
    case fordMachE = "ford_MachE"
    case miniCooperSE = "Mini_MiniCooperSE"
    case renaultZoe = "renault_zoe2"
    case renaultZoeZE40 = "renault_zoe"
    case mgZSEV = "mg_mgzsev"
    case jaguarIPace = "jaguar_ipace2021"
    case jaguarIPace2019 = "jaguar_ipace2019"
    case chevyBolt = "gmc_bolt19"
    case chevyBolt2017 = "gmc_bolt17"
    case hondaENy1 = "honda_eny1"
    case aiwaysU5 = "aiways_u5"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mercedesEQA250: return "Mercedes-Benz EQA 250 (2021)"
        case .hyundaiKiaEGMP, .hkmcIoniq5: return "Hyundai/Kia E-GMP (IONIQ 5 / EV6)"
        case .hkmc2019: return "Hyundai / Kia (Kona / Niro EV)"
        case .hkmc2017: return "Hyundai / Kia (IONIQ Electric / Soul EV 2017)"
        case .volkswagenMEB, .volkswagenMEBABRP: return "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)"
        case .volkswagenEGolf: return "Volkswagen e-Golf (ABRP)"
        case .volkswagenEUp: return "Volkswagen e-Up! (ABRP)"
        case .genericOBD2: return "Generic SAE J1979 OBD-II"
        case .genericEV: return "Generic EV (SAE J1979)"
        case .fordMachE: return "Ford Mustang Mach-E (ABRP)"
        case .miniCooperSE: return "Mini Cooper SE (ABRP)"
        case .renaultZoe: return "Renault Zoe ZE50 (ABRP)"
        case .renaultZoeZE40: return "Renault Zoe ZE40 (ABRP)"
        case .mgZSEV: return "MG ZS EV (ABRP)"
        case .jaguarIPace: return "Jaguar I-Pace 2021+ (ABRP)"
        case .jaguarIPace2019: return "Jaguar I-Pace 2019 (ABRP)"
        case .chevyBolt: return "Chevrolet Bolt EV 2019+ (ABRP)"
        case .chevyBolt2017: return "Chevrolet Bolt EV 2017 (ABRP)"
        case .hondaENy1: return "Honda e:Ny1 (ABRP)"
        case .aiwaysU5: return "Aiways U5 (ABRP)"
        }
    }

    public func makeProfile() -> VehicleProfile {
        switch self {
        case .mercedesEQA250: return MercedesEQA250Profile()
        case .hyundaiKiaEGMP, .hkmcIoniq5: return HyundaiKiaEGMPProfile()
        case .hkmc2019:
            return ABRPProfileLoader.loadProfile(filename: "hkmc_hkmc2019.json", name: "Hyundai / Kia (2019+)", capacityKWh: 64.0) ?? GenericEVProfile()
        case .hkmc2017:
            return ABRPProfileLoader.loadProfile(filename: "hkmc_hkmc2017.json", name: "Hyundai / Kia (2017)", capacityKWh: 28.0) ?? GenericEVProfile()
        case .volkswagenMEB, .volkswagenMEBABRP: return VolkswagenMEBProfile()
        case .volkswagenEGolf:
            return ABRPProfileLoader.loadProfile(filename: "volkswagen_eGolf.json", name: "Volkswagen e-Golf", capacityKWh: 35.8) ?? GenericEVProfile()
        case .volkswagenEUp:
            return ABRPProfileLoader.loadProfile(filename: "volkswagen_eUP.json", name: "Volkswagen e-Up!", capacityKWh: 32.3) ?? GenericEVProfile()
        case .genericOBD2: return GenericOBD2Profile()
        case .genericEV: return GenericEVProfile()
        case .fordMachE:
            return ABRPProfileLoader.loadProfile(filename: "ford_MachE.json", name: "Ford Mustang Mach-E", capacityKWh: 91.0) ?? GenericEVProfile()
        case .miniCooperSE:
            return ABRPProfileLoader.loadProfile(filename: "Mini_MiniCooperSE.json", name: "Mini Cooper SE", capacityKWh: 28.9) ?? GenericEVProfile()
        case .renaultZoe:
            return ABRPProfileLoader.loadProfile(filename: "renault_zoe2.json", name: "Renault Zoe (ZE50)", capacityKWh: 52.0) ?? GenericEVProfile()
        case .renaultZoeZE40:
            return ABRPProfileLoader.loadProfile(filename: "renault_zoe.json", name: "Renault Zoe (ZE40)", capacityKWh: 41.0) ?? GenericEVProfile()
        case .mgZSEV:
            return ABRPProfileLoader.loadProfile(filename: "mg_mgzsev.json", name: "MG ZS EV", capacityKWh: 68.3) ?? GenericEVProfile()
        case .jaguarIPace:
            return ABRPProfileLoader.loadProfile(filename: "jaguar_ipace2021.json", name: "Jaguar I-Pace", capacityKWh: 84.7) ?? GenericEVProfile()
        case .jaguarIPace2019:
            return ABRPProfileLoader.loadProfile(filename: "jaguar_ipace2019.json", name: "Jaguar I-Pace (2019)", capacityKWh: 84.7) ?? GenericEVProfile()
        case .chevyBolt:
            return ABRPProfileLoader.loadProfile(filename: "gmc_bolt19.json", name: "Chevrolet Bolt EV", capacityKWh: 66.0) ?? GenericEVProfile()
        case .chevyBolt2017:
            return ABRPProfileLoader.loadProfile(filename: "gmc_bolt17.json", name: "Chevrolet Bolt EV (2017)", capacityKWh: 60.0) ?? GenericEVProfile()
        case .hondaENy1:
            return ABRPProfileLoader.loadProfile(filename: "honda_eny1.json", name: "Honda e:Ny1", capacityKWh: 68.8) ?? GenericEVProfile()
        case .aiwaysU5:
            return ABRPProfileLoader.loadProfile(filename: "aiways_u5.json", name: "Aiways U5", capacityKWh: 63.0) ?? GenericEVProfile()
        }
    }
}
