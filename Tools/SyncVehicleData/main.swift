import Foundation

private struct SlugName: Decodable {
    let slug: String
    let name: String
}

private struct OpenEVBattery: Decodable {
    let grossKWh: Double?
    let netKWh: Double?

    enum CodingKeys: String, CodingKey {
        case grossKWh = "pack_capacity_kwh_gross"
        case netKWh = "pack_capacity_kwh_net"
    }
}

private struct OpenEVRange: Decodable {
    struct Rating: Decodable {
        let cycle: String
        let rangeKm: Double

        enum CodingKeys: String, CodingKey {
            case cycle
            case rangeKm = "range_km"
        }
    }

    let rated: [Rating]
}

private struct OpenEVSource: Decodable {
    let type: String
    let title: String
    let url: String
    let accessedAt: String

    enum CodingKeys: String, CodingKey {
        case type, title, url
        case accessedAt = "accessed_at"
    }
}

private struct OpenEVRecord: Decodable {
    let schemaVersion: String
    let uniqueCode: String?
    let make: SlugName
    let model: SlugName
    let year: Int
    let trim: SlugName
    let variant: SlugName?
    let battery: OpenEVBattery
    let range: OpenEVRange
    let sources: [OpenEVSource]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case uniqueCode = "unique_code"
        case make, model, year, trim, variant, battery, range, sources
    }
}

private struct OpenEVDataset: Decodable {
    let schemaVersion: String
    let generatedAt: String?
    let vehicleCount: Int?
    let vehicles: [OpenEVRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case vehicleCount = "vehicle_count"
        case vehicles
    }
}

private struct Catalog: Codable {
    var version: String
    var source: String
    var lastUpdated: String?
    var sourceMetadata: SourceMetadata?
    var brands: [Brand]
}

private struct SourceMetadata: Codable {
    let openEVSchemaVersion: String
    let openEVGeneratedAt: String?
    let openEVArtifact: String
    let openEVRecordCount: Int
    let existingCatalogVersion: String
    let abrpMappingArtifact: String?
}

private struct Brand: Codable {
    var id: String
    var name: String
    var iconSymbol: String
    var models: [Model]
}

private struct Model: Codable {
    var id: String
    var brandName: String
    var modelName: String
    var years: String
    var powertrain: String
    var batteryCapacityKWh: Double
    var profileID: String
    var telemetrySupport: String
    var estimatedRangeKm: Double?
    var notes: String?
    var modelFamilyID: String?
    var modelFamilyName: String?
    var variantDisplayName: String?
}

private struct ABRPMapEntry: Decodable {
    let pids: String
}

private let deprecatedProfileAssignments: Set<String> = [
    "mercedes_benz-eqa-0",
    "mercedes_benz-eqb-0"
]

private let familyByProfileID: [String: (slug: String, name: String)] = [
    "Mini_MiniCooperSE": ("mini_cooper_se", "Cooper SE"),
    "aiways_u5": ("u5", "U5"),
    "bmw_i3": ("i3", "i3"),
    "byd_atto3": ("atto_3", "Atto 3"),
    "deepal_s05": ("s05", "S05"),
    "ford_MachE": ("mustang_mach_e", "Mustang Mach-E"),
    "gmc_bolt17": ("bolt_ev", "Bolt EV"),
    "gmc_bolt19": ("bolt_ev", "Bolt EV"),
    "honda_eny1": ("e_ny1", "e:Ny1"),
    "jaguar_ipace2019": ("i_pace", "I-Pace"),
    "jaguar_ipace2021": ("i_pace", "I-Pace"),
    "mg_mgzsev": ("zs_ev", "ZS EV"),
    "nissan_leaf": ("leaf", "Leaf"),
    "renault_zoe": ("zoe", "Zoe"),
    "renault_zoe2": ("zoe", "Zoe"),
    "volkswagen_eGolf": ("e_golf", "e-Golf"),
    "volkswagen_eUP": ("e_up", "e-Up!")
]

private struct Options {
    var openEVPath: String?
    var existingPath = "Data/Seed/vehicle_catalog.json"
    var abrpDirectory = "Data/Seed/abrp_pids"
    var outputPath: String?
    var allowOverwriteExisting = false
}

private enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case invalid(String)

    var description: String {
        switch self {
        case .usage(let message), .invalid(let message): return message
        }
    }
}

private let help = """
VoltLink deterministic vehicle catalog synchronizer

USAGE:
  swift run SyncVehicleData --openev <file-or-checkout> --output <path> [options]

OPTIONS:
  --openev <path>       Compiled OpenEV release JSON, or a local checkout that
                        contains exactly one open-ev-data*.json outside src/.
                        Layered src/ records are intentionally not consumed;
                        compile/download a release artifact into the checkout.
  --existing <path>     Catalog whose IDs, profiles, support labels, and unmatched
                        entries are retained (default: Data/Seed/vehicle_catalog.json).
  --abrp-dir <path>     Bundled profile directory containing obdble_cars.json
                        (default: Data/Seed/abrp_pids).
  --output <path>       Destination JSON. Generation performs no network access.
  --allow-overwrite-existing
                        Permit --output to equal --existing. Existing IDs and
                        telemetry labels are still checked before writing.
  -h, --help            Show this help.

Obtain a source artifact independently, for example:
  git clone https://github.com/open-ev-data/open-ev-data-dataset.git /tmp/open-ev-data
  # Download a pinned release JSON into that checkout, then:
  swift run SyncVehicleData --openev /tmp/open-ev-data/open-ev-data-v1.24.0.json \\
    --output /tmp/vehicle_catalog.json

New OpenEV vehicles default to generic telemetry. A bundled ABRP mapping can
promote them to community support. Verified support is only retained from an
explicitly matching entry in --existing and is never inferred from source data.
"""

private func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--help" || argument == "-h" {
            print(help)
            exit(EXIT_SUCCESS)
        }
        if argument == "--allow-overwrite-existing" {
            options.allowOverwriteExisting = true
            index += 1
            continue
        }
        guard ["--openev", "--existing", "--abrp-dir", "--output"].contains(argument) else {
            throw ToolError.usage("Unknown option: \(argument)\n\n\(help)")
        }
        guard index + 1 < arguments.count else {
            throw ToolError.usage("Missing value for \(argument)\n\n\(help)")
        }
        let value = arguments[index + 1]
        switch argument {
        case "--openev": options.openEVPath = value
        case "--existing": options.existingPath = value
        case "--abrp-dir": options.abrpDirectory = value
        case "--output": options.outputPath = value
        default: break
        }
        index += 2
    }
    guard options.openEVPath != nil, options.outputPath != nil else {
        throw ToolError.usage("--openev and --output are required.\n\n\(help)")
    }
    return options
}

private func canonicalURL(_ path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
}

private func resolveOpenEVArtifact(at path: String) throws -> URL {
    let url = canonicalURL(path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw ToolError.invalid("OpenEV path does not exist: \(url.path)")
    }
    guard isDirectory.boolValue else { return url }

    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw ToolError.invalid("Cannot enumerate OpenEV checkout: \(url.path)")
    }
    let candidates = enumerator.compactMap { item -> URL? in
        guard let itemURL = item as? URL else { return nil }
        let relative = itemURL.path.replacingOccurrences(of: url.path + "/", with: "")
        if relative.hasPrefix("src/") { return nil }
        let name = itemURL.lastPathComponent.lowercased()
        return name.hasPrefix("open-ev-data") && name.hasSuffix(".json") ? itemURL : nil
    }.sorted { $0.path < $1.path }

    guard candidates.count == 1 else {
        let detail = candidates.isEmpty ? "none found" : candidates.map(\.path).joined(separator: ", ")
        throw ToolError.invalid("Expected exactly one compiled open-ev-data*.json in checkout; \(detail). Pass the artifact file directly when multiple versions exist.")
    }
    return candidates[0]
}

private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    } catch {
        throw ToolError.invalid("Invalid JSON schema at \(url.path): \(error)")
    }
}

private func validate(_ dataset: OpenEVDataset) throws {
    guard dataset.schemaVersion == "1.0.0" else {
        throw ToolError.invalid("Unsupported OpenEV schema_version \(dataset.schemaVersion); expected 1.0.0")
    }
    if let declared = dataset.vehicleCount, declared != dataset.vehicles.count {
        throw ToolError.invalid("OpenEV vehicle_count is \(declared), but vehicles contains \(dataset.vehicles.count) records")
    }
    guard !dataset.vehicles.isEmpty else { throw ToolError.invalid("OpenEV dataset contains no vehicles") }

    let slugPattern = try NSRegularExpression(pattern: "^[a-z0-9_]+$")
    func validSlug(_ value: String) -> Bool {
        slugPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
    var identities = Set<String>()
    for (index, vehicle) in dataset.vehicles.enumerated() {
        let label = vehicle.uniqueCode ?? "record \(index)"
        guard vehicle.schemaVersion == dataset.schemaVersion else {
            throw ToolError.invalid("\(label): record schema_version does not match the dataset")
        }
        guard validSlug(vehicle.make.slug), validSlug(vehicle.model.slug), validSlug(vehicle.trim.slug),
              vehicle.make.name.isEmpty == false, vehicle.model.name.isEmpty == false,
              vehicle.trim.name.isEmpty == false, (1900...2100).contains(vehicle.year) else {
            throw ToolError.invalid("\(label): invalid required make/model/trim/year fields")
        }
        guard let capacity = vehicle.battery.netKWh ?? vehicle.battery.grossKWh,
              capacity.isFinite, capacity > 0 else {
            throw ToolError.invalid("\(label): no positive finite net or gross battery capacity")
        }
        guard !vehicle.sources.isEmpty, vehicle.sources.allSatisfy({ source in
            ["oem", "regulatory", "press", "community", "testing_org"].contains(source.type)
                && !source.title.isEmpty && URL(string: source.url)?.scheme != nil && !source.accessedAt.isEmpty
        }) else {
            throw ToolError.invalid("\(label): missing or malformed provenance sources")
        }
        let identity = vehicle.uniqueCode ?? "\(vehicle.make.slug):\(vehicle.model.slug):\(vehicle.year):\(vehicle.trim.slug):\(vehicle.variant?.slug ?? "")"
        guard identities.insert(identity).inserted else {
            throw ToolError.invalid("Duplicate OpenEV identity: \(identity)")
        }
    }
}

private func normalized(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
        .lowercased()
}

private func displayName(for record: OpenEVRecord) -> String {
    var parts = [record.model.name]
    for component in [record.trim.name, record.variant?.name].compactMap({ $0 }) {
        guard normalized(component) != "base", !normalized(parts.joined(separator: " ")).contains(normalized(component)) else { continue }
        parts.append(component)
    }
    return parts.joined(separator: " ")
}

private func variantDisplayName(for record: OpenEVRecord) -> String {
    var parts: [String] = []
    for component in [record.trim.name, record.variant?.name].compactMap({ $0 }) {
        guard normalized(component) != "base", !parts.contains(where: { normalized($0) == normalized(component) }) else { continue }
        parts.append(component)
    }
    return parts.isEmpty ? record.model.name : parts.joined(separator: " · ")
}

private func preferredRange(_ ratings: [OpenEVRange.Rating]) -> Double? {
    for cycle in ["wltp", "epa", "cltc", "nedc", "jc08", "other"] {
        if let value = ratings.first(where: { $0.cycle == cycle })?.rangeKm, value.isFinite, value > 0 { return value }
    }
    return nil
}

private struct GroupKey: Hashable {
    let make: String
    let model: String
    let trim: String
    let variant: String
    let capacityHundredths: Int
}

private func generatedID(for key: GroupKey) -> String {
    let identity = [key.make, key.model, key.trim == "base" ? nil : key.trim, key.variant.isEmpty ? nil : key.variant]
        .compactMap { $0 }
        .joined(separator: "-")
    return "\(identity)-\(key.capacityHundredths)"
}

private func semanticKey(brand: String, model: String) -> String {
    "\(normalized(brand)):\(normalized(model))"
}

private func yearsDescription(_ years: [Int]) -> String {
    let sorted = Array(Set(years)).sorted()
    guard let first = sorted.first else { return "" }
    var ranges: [String] = []
    var start = first
    var previous = first
    for year in sorted.dropFirst() {
        if year == previous + 1 {
            previous = year
        } else {
            ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = year
            previous = year
        }
    }
    ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
    return ranges.joined(separator: ", ")
}

private func wildcardMatch(_ pattern: String, _ value: String) -> Bool {
    let pattern = Array(pattern.lowercased())
    let value = Array(value.lowercased())
    var states = Set([0])
    for character in value {
        var next = Set<Int>()
        for state in states {
            var index = state
            while index < pattern.count, pattern[index] == "*" {
                next.insert(index)
                index += 1
            }
            if index < pattern.count, pattern[index] == character { next.insert(index + 1) }
        }
        states = next
    }
    return states.contains { state in pattern[state...].allSatisfy { $0 == "*" } }
}

private func loadABRPOverlays(directory: URL) throws -> [(pattern: String, profileID: String)] {
    let mapURL = directory.appendingPathComponent("obdble_cars.json")
    guard FileManager.default.fileExists(atPath: mapURL.path) else { return [] }
    let map = try read([String: ABRPMapEntry].self, from: mapURL)
    let availableFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let profileIDs = Set(availableFiles.filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent != "obdble_cars.json" }.map { $0.deletingPathExtension().lastPathComponent })
    let aliases = [
        "u5": "aiways_u5", "eGolf": "volkswagen_eGolf", "MEB": "volkswagen_MEB",
        "zoe": "renault_zoe", "zoe2": "renault_zoe2", "Ioniq5": "hkmc_Ioniq5",
        "hkmc2017": "hkmc_hkmc2017", "hkmc2019": "hkmc_hkmc2019", "MachE": "ford_MachE",
        "ipace2021": "jaguar_ipace2021", "bolt17": "gmc_bolt17", "bolt19": "gmc_bolt19",
        "eUP": "volkswagen_eUP", "mgzsev": "mg_mgzsev", "eny1": "honda_eny1"
    ]
    return map.compactMap { pattern, entry in
        let profileID = aliases[entry.pids] ?? entry.pids
        return profileIDs.contains(profileID) ? (pattern, profileID) : nil
    }.sorted { lhs, rhs in
        if lhs.pattern.count != rhs.pattern.count { return lhs.pattern.count > rhs.pattern.count }
        return lhs.pattern < rhs.pattern
    }
}

private func validateCatalog(_ catalog: Catalog, preserving existing: Catalog) throws {
    let models = catalog.brands.flatMap(\.models)
    let ids = models.map(\.id)
    guard Set(ids).count == ids.count else {
        let duplicate = Dictionary(grouping: ids, by: { $0 }).first { $0.value.count > 1 }!.key
        throw ToolError.invalid("Generated catalog contains duplicate model ID: \(duplicate)")
    }
    let brandIDs = catalog.brands.map(\.id)
    guard Set(brandIDs).count == brandIDs.count else { throw ToolError.invalid("Generated catalog contains duplicate brand IDs") }
    guard models.allSatisfy({ !$0.id.isEmpty && !$0.brandName.isEmpty && !$0.modelName.isEmpty && !$0.years.isEmpty && $0.batteryCapacityKWh.isFinite && ($0.batteryCapacityKWh > 0 || $0.powertrain.contains("ICE")) && ["generic", "community", "verified"].contains($0.telemetrySupport) }) else {
        throw ToolError.invalid("Generated catalog failed schema validation")
    }
    let generatedByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    for old in existing.brands.flatMap(\.models) {
        guard let new = generatedByID[old.id] else { throw ToolError.invalid("Generation would remove existing ID \(old.id)") }
        guard deprecatedProfileAssignments.contains(old.id) || new.telemetrySupport == old.telemetrySupport else {
            throw ToolError.invalid("Generation would change telemetrySupport for \(old.id) from \(old.telemetrySupport) to \(new.telemetrySupport)")
        }
    }
}

private func generate(dataset: OpenEVDataset, artifact: URL, existing: Catalog, abrpDirectory: URL) throws -> Catalog {
    let overlays = try loadABRPOverlays(directory: abrpDirectory)
    var groups: [GroupKey: [OpenEVRecord]] = [:]
    for record in dataset.vehicles {
        let capacity = record.battery.netKWh ?? record.battery.grossKWh!
        let key = GroupKey(
            make: record.make.slug,
            model: record.model.slug,
            trim: record.trim.slug,
            variant: record.variant?.slug ?? "",
            capacityHundredths: Int((capacity * 100).rounded())
        )
        groups[key, default: []].append(record)
    }

    let oldModels = existing.brands.flatMap(\.models)
    let oldBySemantic: [String: [Model]] = Dictionary(grouping: oldModels) { semanticKey(brand: $0.brandName, model: $0.modelName) }
    var consumedOldIDs = Set<String>()
    var generated: [String: [Model]] = [:]

    for (key, records) in groups.sorted(by: { lhs, rhs in
        [lhs.key.make, lhs.key.model, lhs.key.trim, lhs.key.variant, String(lhs.key.capacityHundredths)].lexicographicallyPrecedes([rhs.key.make, rhs.key.model, rhs.key.trim, rhs.key.variant, String(rhs.key.capacityHundredths)])
    }) {
        let records = records.sorted { $0.year < $1.year }
        let representative = records.last!
        let name = displayName(for: representative)
        let semantic = semanticKey(brand: representative.make.name, model: name)
        let generatedID = generatedID(for: key)
        let old = oldModels.first(where: { $0.id == generatedID && !consumedOldIDs.contains($0.id) })
            ?? oldBySemantic[semantic]?
                .filter { !consumedOldIDs.contains($0.id) }
                .min {
                    let targetCapacity = Double(key.capacityHundredths) / 100
                    let lhsDifference = abs($0.batteryCapacityKWh - targetCapacity)
                    let rhsDifference = abs($1.batteryCapacityKWh - targetCapacity)
                    return lhsDifference == rhsDifference ? $0.id < $1.id : lhsDifference < rhsDifference
                }
        if let old { consumedOldIDs.insert(old.id) }

        let matchKey = "\(normalized(representative.make.slug)):\(normalized(representative.model.slug)):\(representative.year)"
        let abrpProfile = overlays.first(where: { wildcardMatch(normalizedPattern($0.pattern), matchKey) })?.profileID
        let inheritedCommunity = oldModels.first(where: {
            $0.telemetrySupport == "community"
                && normalized($0.brandName) == normalized(representative.make.name)
                && (normalized($0.modelName).hasPrefix(normalized(representative.model.name)) || normalized(representative.model.name).hasPrefix(normalized($0.modelName)))
        })
        let isDeprecatedAssignment = old.map { deprecatedProfileAssignments.contains($0.id) } ?? false
        let profileID = isDeprecatedAssignment ? "genericEV" : old?.profileID ?? abrpProfile ?? inheritedCommunity?.profileID ?? "genericEV"
        let support = isDeprecatedAssignment ? "generic" : old?.telemetrySupport ?? (profileID == "genericEV" ? "generic" : "community")
        let capacities = records.map { $0.battery.netKWh ?? $0.battery.grossKWh! }
        let averageCapacity = capacities.reduce(0, +) / Double(capacities.count)
        let ranges = records.compactMap { preferredRange($0.range.rated) }
        let model = Model(
            id: old?.id ?? generatedID,
            brandName: representative.make.name,
            modelName: name,
            years: yearsDescription(records.map(\.year)),
            powertrain: "Electric (BEV)",
            batteryCapacityKWh: Double(Int((averageCapacity * 100).rounded())) / 100,
            profileID: profileID,
            telemetrySupport: support,
            estimatedRangeKm: old?.estimatedRangeKm ?? ranges.max(),
            notes: old?.notes,
            modelFamilyID: "\(representative.make.slug)-\(representative.model.slug)",
            modelFamilyName: representative.model.name,
            variantDisplayName: variantDisplayName(for: representative)
        )
        generated[key.make, default: []].append(model)
    }

    for brand in existing.brands {
        for model in brand.models where !consumedOldIDs.contains(model.id) {
            var retained = model
            if retained.modelFamilyID == nil || retained.modelFamilyID?.hasPrefix("legacy-") == true {
                if let family = familyByProfileID[model.profileID] {
                    retained.modelFamilyID = "\(brand.id)-\(family.slug)"
                    retained.modelFamilyName = family.name
                    retained.variantDisplayName = model.modelName
                } else if let sourceModel = dataset.vehicles
                    .filter({ normalized($0.make.name) == normalized(model.brandName) })
                    .map(\.model)
                    .filter({ normalized(model.modelName).hasPrefix(normalized($0.name)) })
                    .max(by: { $0.name.count < $1.name.count }) {
                    retained.modelFamilyID = "\(brand.id)-\(sourceModel.slug)"
                    retained.modelFamilyName = sourceModel.name
                    retained.variantDisplayName = model.modelName
                } else {
                    retained.modelFamilyID = "legacy-\(model.id)"
                    retained.modelFamilyName = model.modelName
                    retained.variantDisplayName = model.modelName
                }
            }
            if deprecatedProfileAssignments.contains(retained.id) {
                retained.profileID = "genericEV"
                retained.telemetrySupport = "generic"
            }
            generated[brand.id, default: []].append(retained)
        }
    }

    let oldBrands = Dictionary(uniqueKeysWithValues: existing.brands.map { ($0.id, $0) })
    var brands = generated.map { id, models -> Brand in
        let sourceRecord = dataset.vehicles.first { $0.make.slug == id }
        let old = oldBrands[id]
        return Brand(
            id: id,
            name: old?.name ?? sourceRecord?.make.name ?? id,
            iconSymbol: old?.iconSymbol ?? "car.side.fill",
            models: models.sorted {
                let lhs = (normalized($0.modelName), $0.years, $0.id)
                let rhs = (normalized($1.modelName), $1.years, $1.id)
                return lhs < rhs
            }
        )
    }
    brands.sort {
        let lhs = (normalized($0.name), $0.id)
        let rhs = (normalized($1.name), $1.id)
        return lhs < rhs
    }

    let mappingURL = abrpDirectory.appendingPathComponent("obdble_cars.json")
    return Catalog(
        version: "2.0",
        source: existing.source,
        lastUpdated: dataset.generatedAt.map { String($0.prefix(10)) } ?? existing.lastUpdated,
        sourceMetadata: SourceMetadata(
            openEVSchemaVersion: dataset.schemaVersion,
            openEVGeneratedAt: dataset.generatedAt,
            openEVArtifact: artifact.lastPathComponent,
            openEVRecordCount: dataset.vehicles.count,
            existingCatalogVersion: existing.sourceMetadata?.existingCatalogVersion ?? existing.version,
            abrpMappingArtifact: FileManager.default.fileExists(atPath: mappingURL.path) ? mappingURL.lastPathComponent : nil
        ),
        brands: brands
    )
}

private func normalizedPattern(_ pattern: String) -> String {
    pattern.split(separator: ":", omittingEmptySubsequences: false).map { component in
        component.split(separator: "*", omittingEmptySubsequences: false).map { normalized(String($0)) }.joined(separator: "*")
    }.joined(separator: ":")
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let artifact = try resolveOpenEVArtifact(at: options.openEVPath!)
    let existingURL = canonicalURL(options.existingPath)
    let outputURL = canonicalURL(options.outputPath!)
    if outputURL == existingURL && !options.allowOverwriteExisting {
        throw ToolError.usage("Refusing to overwrite --existing without --allow-overwrite-existing")
    }
    guard FileManager.default.fileExists(atPath: outputURL.deletingLastPathComponent().path) else {
        throw ToolError.invalid("Output directory does not exist: \(outputURL.deletingLastPathComponent().path)")
    }

    let dataset = try read(OpenEVDataset.self, from: artifact)
    try validate(dataset)
    let existing = try read(Catalog.self, from: existingURL)
    let catalog = try generate(dataset: dataset, artifact: artifact, existing: existing, abrpDirectory: canonicalURL(options.abrpDirectory))
    try validateCatalog(catalog, preserving: existing)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(catalog)
    data.append(0x0A)
    try data.write(to: outputURL, options: .atomic)
    print("Generated \(catalog.brands.flatMap(\.models).count) vehicles across \(catalog.brands.count) brands at \(outputURL.path)")
    print("Source: \(artifact.lastPathComponent), \(dataset.vehicles.count) validated OpenEV records; network access: none")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
