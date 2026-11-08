import Foundation

/// Read-only after `init` except for user-supplied `importPack` overlays, which are
/// installed under `lock`. `@unchecked Sendable` reflects that discipline rather than
/// papering over mutation: the bundled tables never change, and pack lookups are locked.
public final class DTCLocalDatabase: @unchecked Sendable {
    public static let shared = DTCLocalDatabase()

    private let lock = NSLock()
    private var database: [String: DTCCode] = [:]
    private var definitions: [String: [String: String]] = [:]
    /// Mercedes-Benz module fault numbers that no public OBD-II code table covers.
    private var moduleDefinitions: [String: DTCCode] = [:]
    /// Overlay installed by `importPack`, keyed by base code.
    private var importedDefinitions: [String: DTCCode] = [:]

    private struct ImportedDatabase: Decodable {
        let definitions: [String: [String: String]]
    }

    /// Format of a user-supplied code pack. `schema` guards against silently
    /// misreading a future layout.
    public struct ImportedPack: Decodable, Sendable {
        public let schema: Int
        public let manufacturer: String?
        public let codes: [DTCCode]
    }

    public enum ImportError: LocalizedError {
        case unsupportedSchema(Int)
        case emptyPack

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let schema):
                return "Code pack schema \(schema) is not supported (expected schema 1)."
            case .emptyPack:
                return "The code pack contains no codes."
            }
        }
    }

    /// A missing or invalid resource reduces lookup coverage; scanning can still proceed.
    public private(set) var loadError: String?

    private init() {
        loadBundleDatabase()
        loadModuleDatabase()
        do {
            guard let url = Self.bundle.url(forResource: "wal33d_dtc", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            definitions = try JSONDecoder().decode(ImportedDatabase.self, from: Data(contentsOf: url)).definitions
        } catch {
            loadError = [loadError, "Wal33D DTC definitions could not be loaded — code descriptions are limited."]
                .compactMap { $0 }.joined(separator: " ")
        }
    }

    public func lookup(code: String, manufacturer: String? = nil) -> DTCCode {
        lock.lock()
        defer { lock.unlock() }
        return lookupUnlocked(code: code, manufacturer: manufacturer)
    }

    /// Resolves a UDS fault-memory record: the base code looks up bundled and imported
    /// definitions, and the record keeps its failure-type byte, module and status bits even
    /// when no description exists for it.
    public func lookupUDS(
        saeCode: String,
        failureType: UInt8,
        status: UInt8 = 0,
        module: String,
        manufacturer: String? = nil
    ) -> DTCCode {
        lock.lock()
        defer { lock.unlock() }

        let base = saeCode.uppercased()
        let record = base + String(format: "-%02X", failureType)
        let failure = UDSDiagnostics.failureTypeDescription(failureType)
        let statuses = UDSDiagnostics.statusDescriptions(status)

        if let definition = moduleDefinitions[base] ?? importedDefinitions[base] {
            return DTCCode(
                code: record,
                title: definition.title,
                category: definition.category,
                severity: definition.severity,
                description: definition.description,
                symptoms: definition.symptoms,
                possibleFixes: definition.possibleFixes,
                definitionSource: definition.definitionSource,
                moduleName: module,
                failureTypeDescription: failure,
                statusDescriptions: statuses)
        }

        let fallback = lookupUnlocked(code: base, manufacturer: manufacturer)
        let described = fallback.title != "Diagnostic Code \(base)"
        return DTCCode(
            code: record,
            title: described ? fallback.title : "Manufacturer fault \(record)",
            category: fallback.category,
            severity: described ? fallback.severity : .unknown,
            description: described
                ? fallback.description
                : "\(module) stored fault \(record). \(failure). No description is bundled for this manufacturer code.",
            symptoms: fallback.symptoms,
            possibleFixes: fallback.possibleFixes,
            definitionSource: described ? fallback.definitionSource : "UDS fault memory (ISO 14229) · code text not bundled",
            moduleName: module,
            failureTypeDescription: failure,
            statusDescriptions: statuses)
    }

    /// Installs a user-supplied code pack. Existing definitions for the same base code are
    /// replaced, which is how a car-specific description can be added without shipping
    /// licensed manufacturer data.
    @discardableResult
    public func importPack(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try importPack(data: Data(contentsOf: url))
    }

    @discardableResult
    public func importPack(data: Data) throws -> Int {
        let pack = try JSONDecoder().decode(ImportedPack.self, from: data)
        guard pack.schema == 1 else { throw ImportError.unsupportedSchema(pack.schema) }
        guard !pack.codes.isEmpty else { throw ImportError.emptyPack }

        lock.lock()
        defer { lock.unlock() }
        for code in pack.codes {
            importedDefinitions[code.code.uppercased()] = code
        }
        return pack.codes.count
    }

    private func lookupUnlocked(code: String, manufacturer: String?) -> DTCCode {
        let upperCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let category = Self.category(for: upperCode)

        let brand = manufacturer?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let aliases = [
            "MERCEDES-BENZ": "MERCEDES", "MERCEDES BENZ": "MERCEDES",
            "CHEVROLET": "CHEVY", "VW": "VOLKSWAGEN", "GENERAL MOTORS": "GM",
        ]
        let manufacturerDefinition = brand == "GENERIC" ? nil : definitions[aliases[brand] ?? brand]?[upperCode]
        // Standard definitions take precedence over brand tables that also repeat SAE codes.
        if let found = database[upperCode] {
            return found
        }
        if let imported = importedDefinitions[upperCode] {
            return imported
        }
        if let description = definitions["GENERIC"]?[upperCode] ?? manufacturerDefinition {
            return DTCCode(
                code: upperCode, title: description, category: category,
                severity: .unknown, description: description,
                definitionSource: "Wal33D/dtc-database (MIT) · Community definition")
        }

        return DTCCode(
            code: upperCode,
            title: "Diagnostic Code \(upperCode)",
            category: category,
            severity: .unknown,
            description: "Vehicle reported diagnostic trouble code \(upperCode). Consult vehicle technical manual.",
            symptoms: [],
            possibleFixes: ["Perform system scan using professional diagnostic tool"]
        )
    }

    private static func category(for code: String) -> String {
        switch code.first ?? "P" {
        case "P": return "Powertrain"
        case "C": return "Chassis"
        case "B": return "Body"
        case "U": return "Network / CAN"
        default: return "General System"
        }
    }

    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private func loadBundleDatabase() {
        guard let url = Self.bundle.url(forResource: "dtc_definitions", withExtension: "json") else {
            loadError = "Curated DTC definitions are missing — detailed explanations are limited."
            print("DTC definitions file not found in app bundle.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([DTCCode].self, from: data)
            for item in items {
                database[item.code.uppercased()] = item
            }
        } catch {
            loadError = "Curated DTC definitions could not be loaded — detailed explanations are limited."
            print("Failed to decode DTC definitions JSON: \(error)")
        }
    }

    private func loadModuleDatabase() {
        guard let url = Self.bundle.url(forResource: "mercedes_module_dtcs", withExtension: "json") else {
            loadError = [loadError, "Mercedes module code definitions are missing — module faults show raw identifiers."]
                .compactMap { $0 }.joined(separator: " ")
            return
        }
        do {
            let items = try JSONDecoder().decode([DTCCode].self, from: Data(contentsOf: url))
            for item in items {
                moduleDefinitions[item.code.uppercased()] = item
            }
        } catch {
            loadError = [loadError, "Mercedes module code definitions could not be loaded — module faults show raw identifiers."]
                .compactMap { $0 }.joined(separator: " ")
        }
    }
}
