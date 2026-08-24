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

public struct VehicleBrand: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let iconSymbol: String
    public let models: [VehicleModelEntry]

    /// Asset image name corresponding to CarBrands in Assets.xcassets
    public var assetImageName: String {
        "CarBrands/\(id.replacingOccurrences(of: "_", with: "-"))"
    }
}

private struct VehicleCatalogContainer: Codable {
    let version: String?
    let source: String?
    let brands: [VehicleBrand]
}

public struct VehicleCatalog {
    public static let dataSource = "OpenEV Data Dataset & Iternio EV-OBD-PIDs"

    public static let brands: [VehicleBrand] = loadCatalogFromData()

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

    private static func loadCatalogFromData() -> [VehicleBrand] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        if let url = bundle.url(forResource: "vehicle_catalog", withExtension: "json") ??
                     bundle.url(forResource: "vehicle_catalog", withExtension: "json", subdirectory: "Seed"),
           let data = try? Data(contentsOf: url),
           let container = try? JSONDecoder().decode(VehicleCatalogContainer.self, from: data) {
            let brands = container.brands.compactMap { brand -> VehicleBrand? in
                let models = brand.models.filter {
                    $0.batteryCapacityKWh > 0 &&
                    ($0.profileID != .mercedesEQA250 || $0.id == defaultModel.id)
                }
                guard !models.isEmpty else { return nil }
                return VehicleBrand(id: brand.id, name: brand.name, iconSymbol: brand.iconSymbol, models: models)
            }

            if !brands.isEmpty {
                return brands.map { brand in
                    guard brand.name == defaultModel.brandName,
                          !brand.models.contains(where: { $0.id == defaultModel.id }) else { return brand }
                    return VehicleBrand(id: brand.id, name: brand.name, iconSymbol: brand.iconSymbol, models: [defaultModel] + brand.models)
                }
            }
        }

        // Fallback minimal default
        return [
            VehicleBrand(
                id: "mercedes",
                name: "Mercedes-Benz",
                iconSymbol: "star.circle.fill",
                models: [defaultModel]
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
    }
}
