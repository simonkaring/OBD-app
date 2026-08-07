import Foundation

public final class DTCLocalDatabase {
    public static let shared = DTCLocalDatabase()

    private var database: [String: DTCCode] = [:]

    private init() {
        loadBundleDatabase()
    }

    public func lookup(code: String) -> DTCCode {
        let upperCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let found = database[upperCode] {
            return found
        }

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

        return DTCCode(
            code: upperCode,
            title: "Diagnostic Code \(upperCode)",
            category: category,
            severity: .warning,
            description: "Vehicle reported diagnostic trouble code \(upperCode). Consult vehicle technical manual.",
            symptoms: ["Check engine / EV warning light illuminated"],
            possibleFixes: ["Perform system scan using professional diagnostic tool"]
        )
    }

    private func loadBundleDatabase() {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "dtc_definitions", withExtension: "json") else { return }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([DTCCode].self, from: data)
            for item in items {
                database[item.code.uppercased()] = item
            }
        } catch {
            print("Failed to decode DTC definitions JSON: \(error)")
        }
    }
}
