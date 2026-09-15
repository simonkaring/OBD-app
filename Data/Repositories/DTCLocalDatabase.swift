import Foundation

public final class DTCLocalDatabase {
    public static let shared = DTCLocalDatabase()

    private var database: [String: DTCCode] = [:]
    private var definitions: [String: [String: String]] = [:]

    private struct ImportedDatabase: Decodable {
        let definitions: [String: [String: String]]
    }

    /// A missing or invalid resource reduces lookup coverage; scanning can still proceed.
    public private(set) var loadError: String?

    private init() {
        loadBundleDatabase()
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
        let upperCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Generic fallback description generator if code not in database
        let category: String
        let firstChar = upperCode.first ?? "P"
        switch firstChar {
        case "P": category = "Powertrain"
        case "C": category = "Chassis"
        case "B": category = "Body"
        case "U": category = "Network / CAN"
        default: category = "General System"
        }

        let brand = manufacturer?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let aliases = ["MERCEDES-BENZ": "MERCEDES", "MERCEDES BENZ": "MERCEDES",
                       "CHEVROLET": "CHEVY", "VW": "VOLKSWAGEN", "GENERAL MOTORS": "GM"]
        let manufacturerDefinition = brand == "GENERIC" ? nil : definitions[aliases[brand] ?? brand]?[upperCode]
        // Standard definitions take precedence over brand tables that also repeat SAE codes.
        if let found = database[upperCode] {
            return found
        }
        if let description = definitions["GENERIC"]?[upperCode] ?? manufacturerDefinition {
            var result = DTCCode(code: upperCode, title: description, category: category,
                                 severity: .unknown, description: description)
            result.definitionSource = "Wal33D/dtc-database (MIT) · Community definition"
            return result
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
}
