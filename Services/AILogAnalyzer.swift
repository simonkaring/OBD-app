import Foundation
import Combine
import Security

@MainActor
final class AIAPIKeyStore: ObservableObject {
    static let shared = AIAPIKeyStore()
    @Published private(set) var value = ""
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let write: (String) throws -> Void

    init(defaults: UserDefaults = .standard, read: (() throws -> String)? = nil, write: ((String) throws -> Void)? = nil) {
        self.defaults = defaults
        self.write = write ?? Self.writeKeychain
        do {
            value = try (read ?? Self.readKeychain)()
            if value.isEmpty, let legacy = defaults.string(forKey: "aiApiKey"), !legacy.isEmpty {
                save(legacy)
            } else {
                defaults.removeObject(forKey: "aiApiKey")
            }
        } catch {
            errorMessage = "Could not read the API key: \(error.localizedDescription)"
        }
    }

    func save(_ key: String) {
        do {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            try write(trimmed)
            value = trimmed
            defaults.removeObject(forKey: "aiApiKey")
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the API key: \(error.localizedDescription)"
        }
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "VoltLink.AILogAnalyzer",
         kSecAttrAccount as String: "apiKey"]
    }

    private static func readKeychain() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func writeKeychain(_ key: String) throws {
        let status: OSStatus
        if key.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            status = result == errSecItemNotFound ? errSecSuccess : result
        } else {
            let attributes = [kSecValueData as String: Data(key.utf8),
                              kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as [String: Any]
            let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if result == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            } else {
                status = result
            }
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

public enum AILogAnalyzerError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidURL
    case networkError(String)
    case invalidResponse(Int)
    case decodingError(String)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Please provide an API Key in Developer Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse(let statusCode):
            return "Server returned HTTP status code \(statusCode)."
        case .decodingError(let msg):
            return "Failed to parse AI response: \(msg)"
        case .apiError(let msg):
            return "AI API Error: \(msg)"
        }
    }
}

public struct AILogAnalyzer: Sendable {
    public static func buildAnalysisPrompt(log: [OBDLogEntry], vehicleContext: String = "") -> String {
        var text = """
        You are an expert automotive embedded systems engineer specializing in reverse engineering OBD-II (SAE J1979) and UDS (ISO 14229 / ISO 15765-4) CAN bus diagnostics for Electric Vehicles (EVs) and ICE cars.

        Vehicle Context: \(vehicleContext.isEmpty ? "Unknown / Not specified" : vehicleContext)

        Below is a trace of OBD commands sent to the vehicle and the raw hex responses received:

        ---
        """

        for entry in log {
            text += "\nTimestamp: \(entry.timestamp.ISO8601Format())\nSent: \(entry.sent)\nResponse:\n\(entry.response)\n"
        }

        text += """
        ---

        Please analyze the raw response data:
        1. Identify which ECUs/headers responded (e.g. BMS, Powertrain, Inverter, Charger, Gateway).
        2. Identify candidate PIDs/DIDs and positive responses (e.g. `62 xx xx` for UDS Service 0x22, `41 xx` for OBD-II Mode 01).
        3. For key EV metrics (State of Charge %, Pack Voltage, Pack Current / Power kW, Battery Temperatures, 12V Aux Voltage), identify candidate byte positions and formulas (e.g., bit scaling, offsets, signed vs unsigned integers).
        4. Provide ready-to-use Swift decoding snippet or a `VehicleProfile` implementation for VoltLink.
        """
        return text
    }

    public static func analyze(log: [OBDLogEntry], vehicleContext: String = "", apiKey: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AILogAnalyzerError.missingAPIKey
        }

        let prompt = buildAnalysisPrompt(log: log, vehicleContext: vehicleContext)

        if trimmedKey.hasPrefix("sk-") {
            return try await queryOpenAI(prompt: prompt, apiKey: trimmedKey)
        } else {
            // Default to Gemini API (standard Google API keys start with AIza or other formats)
            return try await queryGemini(prompt: prompt, apiKey: trimmedKey)
        }
    }

    private static func queryGemini(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)") else {
            throw AILogAnalyzerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2
            ]
        ]

        let httpBody: Data
        do {
            httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AILogAnalyzerError.decodingError(error.localizedDescription)
        }
        request.httpBody = httpBody

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AILogAnalyzerError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                throw AILogAnalyzerError.apiError(msg)
            }
            throw AILogAnalyzerError.invalidResponse(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AILogAnalyzerError.decodingError("Unexpected Gemini response structure.")
        }

        return text
    }

    private static func queryOpenAI(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AILogAnalyzerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an automotive reverse engineering expert specializing in OBD-II and UDS CAN bus diagnostic decoding."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        let httpBody: Data
        do {
            httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AILogAnalyzerError.decodingError(error.localizedDescription)
        }
        request.httpBody = httpBody

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AILogAnalyzerError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let msg = errorObj["message"] as? String {
                throw AILogAnalyzerError.apiError(msg)
            }
            throw AILogAnalyzerError.invalidResponse(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AILogAnalyzerError.decodingError("Unexpected OpenAI response structure.")
        }

        return content
    }
}
