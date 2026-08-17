import Foundation

public enum PowertrainType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ev = "Electric (BEV)"
    case phev = "Plug-in Hybrid (PHEV)"
    case ice = "Gasoline / Diesel (ICE)"

    public var id: String { rawValue }

    public var badgeIcon: String {
        switch self {
        case .ev: return "bolt.car.fill"
        case .phev: return "bolt.horizontal.fill"
        case .ice: return "fuelpump.fill"
        }
    }
}

/// Describes the best telemetry path available for a catalog vehicle. Static
/// specifications are always available; live values still depend on the car.
public enum LiveTelemetrySupport: String, Codable, Sendable {
    case verified
    case community
    case generic

    public var displayName: String {
        switch self {
        case .verified: return "Verified live telemetry"
        case .community: return "Community live telemetry"
        case .generic: return "Generic OBD telemetry"
        }
    }
}

public struct VehicleModelEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let brandName: String
    public let modelName: String
    public let years: String
    public let powertrain: PowertrainType
    public let batteryCapacityKWh: Double
    public let profileID: VehicleProfileID
    public let telemetrySupport: LiveTelemetrySupport

    public init(
        id: String,
        brandName: String,
        modelName: String,
        years: String,
        powertrain: PowertrainType,
        batteryCapacityKWh: Double,
        profileID: VehicleProfileID,
        telemetrySupport: LiveTelemetrySupport = .generic
    ) {
        self.id = id
        self.brandName = brandName
        self.modelName = modelName
        self.years = years
        self.powertrain = powertrain
        self.batteryCapacityKWh = batteryCapacityKWh
        self.profileID = profileID
        self.telemetrySupport = telemetrySupport
    }

    public var fullName: String {
        "\(brandName) \(modelName)"
    }
}

public struct VehicleBrand: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let iconSymbol: String
    public let models: [VehicleModelEntry]
}

public struct VehicleCatalog {
    /// Capacity values are usable-pack values curated from public manufacturer
    /// specifications. Replace this catalog with a pinned OpenEV Data snapshot
    /// when the release-update tool can fetch upstream data.
    public static let dataSource = "Bundled EV specifications"

    public static let brands: [VehicleBrand] = [
        VehicleBrand(
            id: "tesla",
            name: "Tesla",
            iconSymbol: "bolt.shield.fill",
            models: [
                VehicleModelEntry(id: "tsla-m3-sr", brandName: "Tesla", modelName: "Model 3 Standard Range", years: "2017-2024", powertrain: .ev, batteryCapacityKWh: 60.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "tsla-m3-lr", brandName: "Tesla", modelName: "Model 3 Long Range / Perf", years: "2017-2024", powertrain: .ev, batteryCapacityKWh: 78.1, profileID: .genericOBD2),
                VehicleModelEntry(id: "tsla-my-lr", brandName: "Tesla", modelName: "Model Y Long Range", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 78.1, profileID: .genericOBD2),
                VehicleModelEntry(id: "tsla-my-p", brandName: "Tesla", modelName: "Model Y Performance", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 78.1, profileID: .genericOBD2),
                VehicleModelEntry(id: "tsla-ms-plaid", brandName: "Tesla", modelName: "Model S / Plaid", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 100.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "tsla-mx-plaid", brandName: "Tesla", modelName: "Model X / Plaid", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 100.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "tsla-ct", brandName: "Tesla", modelName: "Cybertruck AWD / Cyberbeast", years: "2023-2024", powertrain: .ev, batteryCapacityKWh: 123.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "mercedes",
            name: "Mercedes-Benz",
            iconSymbol: "star.circle.fill",
            models: [
                VehicleModelEntry(id: "mb-eqa-250", brandName: "Mercedes-Benz", modelName: "EQA 250", years: "2021", powertrain: .ev, batteryCapacityKWh: 66.5, profileID: .mercedesEQA250, telemetrySupport: .verified),
                VehicleModelEntry(id: "mb-eqb-300", brandName: "Mercedes-Benz", modelName: "EQB 300 4MATIC", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 66.5, profileID: .genericOBD2),
                VehicleModelEntry(id: "mb-eqc-400", brandName: "Mercedes-Benz", modelName: "EQC 400 4MATIC", years: "2019-2023", powertrain: .ev, batteryCapacityKWh: 80.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "mb-eqe-350", brandName: "Mercedes-Benz", modelName: "EQE 350+ Sedan / SUV", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 90.6, profileID: .genericOBD2),
                VehicleModelEntry(id: "mb-eqs-450", brandName: "Mercedes-Benz", modelName: "EQS 450+ / 580 Sedan", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 107.8, profileID: .genericOBD2),
                VehicleModelEntry(id: "mb-g580-eq", brandName: "Mercedes-Benz", modelName: "G 580 with EQ Technology", years: "2024+", powertrain: .ev, batteryCapacityKWh: 116.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "bmw",
            name: "BMW",
            iconSymbol: "car.side.fill",
            models: [
                VehicleModelEntry(id: "bmw-i4-m50", brandName: "BMW", modelName: "i4 eDrive40 / M50", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 80.7, profileID: .genericOBD2),
                VehicleModelEntry(id: "bmw-ix-50", brandName: "BMW", modelName: "iX xDrive50 / M60", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 105.2, profileID: .genericOBD2),
                VehicleModelEntry(id: "bmw-i7-60", brandName: "BMW", modelName: "i7 xDrive60", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 101.7, profileID: .genericOBD2),
                VehicleModelEntry(id: "bmw-ix3", brandName: "BMW", modelName: "iX3", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 74.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "bmw-i3", brandName: "BMW", modelName: "i3 / i3s (94Ah / 120Ah)", years: "2013-2022", powertrain: .ev, batteryCapacityKWh: 37.9, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "audi",
            name: "Audi",
            iconSymbol: "circle.grid.2x2.fill",
            models: [
                VehicleModelEntry(id: "audi-q4-etron", brandName: "Audi", modelName: "Q4 e-tron 40 / 50", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 77.0, profileID: .volkswagenMEB, telemetrySupport: .community),
                VehicleModelEntry(id: "audi-q8-etron", brandName: "Audi", modelName: "Q8 e-tron / Sportback", years: "2023-2024", powertrain: .ev, batteryCapacityKWh: 106.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "audi-etron-gt", brandName: "Audi", modelName: "e-tron GT / RS e-tron GT", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 83.7, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "porsche",
            name: "Porsche",
            iconSymbol: "shield.fill",
            models: [
                VehicleModelEntry(id: "por-taycan-4s", brandName: "Porsche", modelName: "Taycan / 4S / Turbo S", years: "2019-2024", powertrain: .ev, batteryCapacityKWh: 83.7, profileID: .genericOBD2),
                VehicleModelEntry(id: "por-taycan-ct", brandName: "Porsche", modelName: "Taycan Cross / Sport Turismo", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 83.7, profileID: .genericOBD2),
                VehicleModelEntry(id: "por-macan-ev", brandName: "Porsche", modelName: "Macan EV Turbo", years: "2024+", powertrain: .ev, batteryCapacityKWh: 95.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "vw",
            name: "Volkswagen",
            iconSymbol: "car.2.fill",
            models: [
                VehicleModelEntry(id: "vw-id3", brandName: "Volkswagen", modelName: "ID.3 Pro / Pro S", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 58.0, profileID: .volkswagenMEB, telemetrySupport: .community),
                VehicleModelEntry(id: "vw-id4", brandName: "Volkswagen", modelName: "ID.4 Pro / GTX", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 77.0, profileID: .volkswagenMEB, telemetrySupport: .community),
                VehicleModelEntry(id: "vw-id5", brandName: "Volkswagen", modelName: "ID.5 GTX", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 77.0, profileID: .volkswagenMEB, telemetrySupport: .community),
                VehicleModelEntry(id: "vw-idbuzz", brandName: "Volkswagen", modelName: "ID. Buzz Pro / LWB", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 77.0, profileID: .volkswagenMEB, telemetrySupport: .community)
            ]
        ),
        VehicleBrand(
            id: "hyundai",
            name: "Hyundai",
            iconSymbol: "car.circle.fill",
            models: [
                VehicleModelEntry(id: "hy-ioniq5-77", brandName: "Hyundai", modelName: "IONIQ 5 Long Range", years: "2022", powertrain: .ev, batteryCapacityKWh: 77.4, profileID: .hyundaiKiaEGMP, telemetrySupport: .community),
                VehicleModelEntry(id: "hy-ioniq5-n", brandName: "Hyundai", modelName: "IONIQ 5 N", years: "2024+", powertrain: .ev, batteryCapacityKWh: 84.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "hy-ioniq6-77", brandName: "Hyundai", modelName: "IONIQ 6 Long Range", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 77.4, profileID: .genericOBD2),
                VehicleModelEntry(id: "hy-kona-ev", brandName: "Hyundai", modelName: "Kona Electric (64 kWh)", years: "2018-2024", powertrain: .ev, batteryCapacityKWh: 64.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "kia",
            name: "Kia",
            iconSymbol: "car.fill",
            models: [
                VehicleModelEntry(id: "kia-ev6-gt", brandName: "Kia", modelName: "EV6 GT / Long Range", years: "2022", powertrain: .ev, batteryCapacityKWh: 77.4, profileID: .hyundaiKiaEGMP, telemetrySupport: .community),
                VehicleModelEntry(id: "kia-ev9-gt", brandName: "Kia", modelName: "EV9 GT-Line (99.8 kWh)", years: "2023-2024", powertrain: .ev, batteryCapacityKWh: 99.8, profileID: .genericOBD2),
                VehicleModelEntry(id: "kia-niro-ev", brandName: "Kia", modelName: "Niro EV (64.8 kWh)", years: "2018-2024", powertrain: .ev, batteryCapacityKWh: 64.8, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "ford",
            name: "Ford",
            iconSymbol: "bolt.car.fill",
            models: [
                VehicleModelEntry(id: "ford-mache-er", brandName: "Ford", modelName: "Mustang Mach-E Extended Range", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 91.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "ford-f150-lightning", brandName: "Ford", modelName: "F-150 Lightning ER", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 131.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "chevrolet",
            name: "Chevrolet",
            iconSymbol: "bolt.fill",
            models: [
                VehicleModelEntry(id: "chevy-bolt-ev", brandName: "Chevrolet", modelName: "Bolt EV / EUV", years: "2017-2023", powertrain: .ev, batteryCapacityKWh: 65.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "chevy-blazer-ev", brandName: "Chevrolet", modelName: "Blazer EV RS / SS", years: "2023-2024", powertrain: .ev, batteryCapacityKWh: 85.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "chevy-equinox-ev", brandName: "Chevrolet", modelName: "Equinox EV LT / RS", years: "2024+", powertrain: .ev, batteryCapacityKWh: 85.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "nissan",
            name: "Nissan",
            iconSymbol: "leaf.fill",
            models: [
                VehicleModelEntry(id: "nissan-leaf-62", brandName: "Nissan", modelName: "LEAF e+ (62 kWh)", years: "2019-2024", powertrain: .ev, batteryCapacityKWh: 59.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "nissan-ariya-87", brandName: "Nissan", modelName: "Ariya e-4ORCE (87 kWh)", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 87.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "polestar_volvo",
            name: "Volvo / Polestar",
            iconSymbol: "shield.checkered",
            models: [
                VehicleModelEntry(id: "polestar-2-lr", brandName: "Polestar", modelName: "Polestar 2 Long Range Dual", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 78.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "polestar-3", brandName: "Polestar", modelName: "Polestar 3 Long Range", years: "2024+", powertrain: .ev, batteryCapacityKWh: 107.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "volvo-ex30", brandName: "Volvo", modelName: "EX30 Ultra Single / Twin", years: "2024+", powertrain: .ev, batteryCapacityKWh: 64.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "volvo-xc40-recharge", brandName: "Volvo", modelName: "XC40 / C40 Recharge", years: "2020-2024", powertrain: .ev, batteryCapacityKWh: 78.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "rivian",
            name: "Rivian",
            iconSymbol: "mountain.2.fill",
            models: [
                VehicleModelEntry(id: "rivian-r1t-large", brandName: "Rivian", modelName: "R1T Quad-Motor (Large Pack)", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 135.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "rivian-r1s-max", brandName: "Rivian", modelName: "R1S Dual-Motor (Max Pack)", years: "2022-2024", powertrain: .ev, batteryCapacityKWh: 149.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "lucid",
            name: "Lucid Motors",
            iconSymbol: "sparkles",
            models: [
                VehicleModelEntry(id: "lucid-air-grand", brandName: "Lucid Motors", modelName: "Air Grand Touring", years: "2021-2024", powertrain: .ev, batteryCapacityKWh: 112.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "lucid-air-pure", brandName: "Lucid Motors", modelName: "Air Pure RWD", years: "2023-2024", powertrain: .ev, batteryCapacityKWh: 88.0, profileID: .genericOBD2)
            ]
        ),
        VehicleBrand(
            id: "generic",
            name: "Generic OBD-II & Others",
            iconSymbol: "wrench.and.screwdriver.fill",
            models: [
                VehicleModelEntry(id: "generic-sae-j1979", brandName: "Generic", modelName: "Standard SAE J1979 (Gas / Hybrid)", years: "1996+", powertrain: .ice, batteryCapacityKWh: 0.0, profileID: .genericOBD2),
                VehicleModelEntry(id: "generic-ev-can", brandName: "Generic", modelName: "Standard EV CAN Bus Profile", years: "2015+", powertrain: .ev, batteryCapacityKWh: 60.0, profileID: .genericOBD2)
            ]
        )
    ]

    public static var allModels: [VehicleModelEntry] {
        brands.flatMap { $0.models }
    }

    public static let defaultModel = VehicleModelEntry(
        id: "mb-eqa-250",
        brandName: "Mercedes-Benz",
        modelName: "EQA 250",
        years: "2021",
        powertrain: .ev,
        batteryCapacityKWh: 66.5,
        profileID: .mercedesEQA250,
        telemetrySupport: .verified
    )
}
