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
    public let estimatedRangeKm: Double?
    public let notes: String?
    public let modelFamilyID: String?
    public let modelFamilyName: String?
    public let variantDisplayName: String?

    public init(
        id: String,
        brandName: String,
        modelName: String,
        years: String,
        powertrain: PowertrainType,
        batteryCapacityKWh: Double,
        profileID: VehicleProfileID,
        telemetrySupport: LiveTelemetrySupport = .generic,
        estimatedRangeKm: Double? = nil,
        notes: String? = nil,
        modelFamilyID: String? = nil,
        modelFamilyName: String? = nil,
        variantDisplayName: String? = nil
    ) {
        self.id = id
        self.brandName = brandName
        self.modelName = modelName
        self.years = years
        self.powertrain = powertrain
        self.batteryCapacityKWh = batteryCapacityKWh
        self.profileID = profileID
        self.telemetrySupport = telemetrySupport
        self.estimatedRangeKm = estimatedRangeKm
        self.notes = notes
        self.modelFamilyID = modelFamilyID
        self.modelFamilyName = modelFamilyName
        self.variantDisplayName = variantDisplayName
    }

    public var fullName: String {
        "\(brandName) \(modelName)"
    }

    public var resolvedVariantDisplayName: String {
        variantDisplayName ?? modelName
    }

    /// Expand the catalog's year labels, preserving gaps such as "2023, 2025".
    /// Open-ended entries include the next model year; closed ranges stay exact.
    public func modelYears(through latestYear: Int = Calendar.current.component(.year, from: .now) + 1) -> [Int] {
        var result = Set<Int>()
        // Hand-maintained entries may append a qualification, e.g. "2021 · experimental".
        for segment in years.components(separatedBy: "·")[0].components(separatedBy: ",") {
            let label = segment.filter { !$0.isWhitespace }.replacingOccurrences(of: "–", with: "-")
            guard label.range(of: #"^[0-9]{4}(-[0-9]{4}|\+)?$"#, options: .regularExpression) != nil,
                  let first = Int(label.prefix(4)) else { return [] }
            let last = label.hasSuffix("+") ? max(first, latestYear) : Int(label.suffix(4))!
            guard first <= last, last <= 9999 else { return [] }
            result.formUnion(first...last)
        }
        return result.sorted(by: >)
    }
}

public struct VehicleModelFamily: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let variants: [VehicleModelEntry]

    public var modelYears: [Int] {
        Set(variants.flatMap { $0.modelYears() }).sorted(by: >)
    }

    public func variants(forModelYear year: Int) -> [VehicleModelEntry] {
        variants.filter { $0.modelYears().contains(year) }
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

    public var modelFamilies: [VehicleModelFamily] {
        VehicleCatalog.modelFamilies(for: models)
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

    public static func modelFamilies(for models: [VehicleModelEntry]) -> [VehicleModelFamily] {
        struct FamilyKey: Hashable {
            let explicitID: String?
            let legacyName: String?
        }

        let grouped = Dictionary(grouping: models) { model in
            if let familyID = model.modelFamilyID, !familyID.isEmpty {
                return FamilyKey(explicitID: familyID, legacyName: nil)
            }

            // Legacy rows have no hierarchy. Group only identical display metadata;
            // leaf IDs are opaque and must not be interpreted for model information.
            let familyName = model.modelFamilyName ?? model.modelName
            return FamilyKey(
                explicitID: nil,
                legacyName: familyName.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            )
        }

        return grouped.values.map { variants in
            let sortedVariants = variants.sorted {
                let result = $0.resolvedVariantDisplayName.localizedStandardCompare($1.resolvedVariantDisplayName)
                return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
            }
            let first = sortedVariants[0]
            return VehicleModelFamily(
                id: first.modelFamilyID ?? "legacy:\(sortedVariants.map(\.id).min() ?? first.id)",
                name: first.modelFamilyName ?? first.modelName,
                variants: sortedVariants
            )
        }.sorted {
            let result = $0.name.localizedStandardCompare($1.name)
            return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
        }
    }

    public static let defaultModel = VehicleModelEntry(
        id: "mb-eqa-250",
        brandName: "Mercedes-Benz",
        modelName: "EQA 250",
        years: "2021",
        powertrain: .ev,
        batteryCapacityKWh: 66.5,
        profileID: .mercedesEQA250,
        telemetrySupport: .verified,
        notes: "Pack-voltage decoding only. SOC and SOC-derived charging are unavailable; DID 0x0210 is retained for raw capture pending validation.",
        modelFamilyID: "mercedes_benz-eqa",
        modelFamilyName: "EQA",
        variantDisplayName: "EQA 250 · 2021"
    )

    public static let eqaOBDbModel = VehicleModelEntry(
        id: "mb-eqa-250-obdb",
        brandName: "Mercedes-Benz",
        modelName: "EQA 250 (OBDb community)",
        years: "2021 · experimental",
        powertrain: .ev,
        batteryCapacityKWh: 66.5,
        profileID: .mercedesEQAOBDb,
        telemetrySupport: .community,
        notes: "Experimental 11-bit OBDb requests. SOC, voltage, current, wheel speed, 12 V and HV coolant temperature. Validate readings and current direction on your car; coolant is not cell temperature.",
        modelFamilyID: "mercedes_benz-eqa",
        modelFamilyName: "EQA",
        variantDisplayName: "EQA 250 · OBDb community (experimental)"
    )

    public static let genericEVModel = VehicleModelEntry(
        id: "generic-ev-can",
        brandName: "Generic",
        modelName: "Standard EV CAN Bus Profile",
        years: "2015+",
        powertrain: .ev,
        batteryCapacityKWh: 60.0,
        profileID: .genericEV,
        telemetrySupport: .generic
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
                let models = brand.models
                    .filter {
                        // A zero pack size means a bad dataset row for a BEV/PHEV, but is
                        // correct for an ICE entry — don't let the sanity check eat those.
                        ($0.batteryCapacityKWh > 0 || $0.powertrain == .ice) &&
                        ($0.profileID != .mercedesEQA250 || $0.id == defaultModel.id)
                    }
                    .sorted { $0.modelName.localizedStandardCompare($1.modelName) == .orderedAscending }
                guard !models.isEmpty else { return nil }
                return VehicleBrand(id: brand.id, name: brand.name, iconSymbol: brand.iconSymbol, models: models)
            }

            if !brands.isEmpty {
                let mapped = brands.map { brand -> VehicleBrand in
                    guard brand.name == defaultModel.brandName else { return brand }
                    let additions = [defaultModel, eqaOBDbModel].filter { model in
                        !brand.models.contains(where: { $0.id == model.id })
                    }
                    let updatedModels = (additions + brand.models).sorted { $0.modelName.localizedStandardCompare($1.modelName) == .orderedAscending }
                    return VehicleBrand(id: brand.id, name: brand.name, iconSymbol: brand.iconSymbol, models: updatedModels)
                }
                return mapped.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }

        // Fallback minimal default
        return [
            VehicleBrand(
                id: "generic",
                name: "Generic OBD-II & Others",
                iconSymbol: "wrench.and.screwdriver.fill",
                models: [
                    VehicleModelEntry(id: "generic-ev-can", brandName: "Generic", modelName: "Standard EV CAN Bus Profile", years: "2015+", powertrain: .ev, batteryCapacityKWh: 60.0, profileID: .genericEV),
                    VehicleModelEntry(id: "generic-sae-j1979", brandName: "Generic", modelName: "Standard SAE J1979 (Gas / Hybrid)", years: "1996+", powertrain: .ice, batteryCapacityKWh: 0.0, profileID: .genericOBD2)
                ]
            ),
            VehicleBrand(
                id: "mercedes",
                name: "Mercedes-Benz",
                iconSymbol: "star.circle.fill",
                models: [defaultModel, eqaOBDbModel]
            )
        ].sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
