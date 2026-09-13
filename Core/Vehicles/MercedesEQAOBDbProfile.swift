import Foundation

/// Adapted from OBDb/Mercedes-Benz-EQA contributors, signalsets/v3/default.json
/// (retrieved 2026-09-13). This adaptation is licensed CC BY-SA 4.0:
/// https://creativecommons.org/licenses/by-sa/4.0/
/// Source: https://github.com/OBDb/Mercedes-Benz-EQA/blob/main/signalsets/v3/default.json
/// Provided as-is, without warranties; see Section 5 of the license.
/// Changes: Swift decoding of a telemetry subset, explicit ELM routing and SOC
/// validation. Other physical bounds are enforced by the telemetry manager instead
/// of upstream display maxima (which cap HV voltage at 100 V).
/// Upstream marks these commands dbg:true. Addressing and current polarity still
/// need vehicle validation; VoltLink interprets negative current as energy entering the pack.
public struct MercedesEQAOBDbProfile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (OBDb community)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh = 66.5
    public let estimatedFullRangeKm = 426.0

    public static let sourceURL = URL(string: "https://github.com/OBDb/Mercedes-Benz-EQA/blob/main/signalsets/v3/default.json")!
    public static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!

    public init() {}

    public var initializationCommands: [String] {
        ["AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT CAF 1",
         "AT SP 6", "AT ST FF", "AT CFC 1", "AT FCSM 0",
         "AT CRA 7ED", "AT SH 7E5"]
    }

    public var pollingCommands: [String] {
        // Poll wheel speed first so pack-current charging inference has a stationary reading.
        ["AT CRA 7EA", "AT SH 7E2", "222001",
         "AT CRA 7ED", "AT SH 7E5", "226050", "226075", "226053", "222005", "222526"]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.soc, .packVoltage, .packCurrent, .power, .speed, .aux12V, .coolantTemp]
    }

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let command = command.replacingOccurrences(of: " ", with: "").uppercased()
        guard ["222001", "226050", "226075", "226053", "222005", "222526"].contains(command) else { return nil }
        let expectedECU = command == "222001" ? "7EA" : "7ED"
        // Headers are required by this profile. Never decode another ECU's reply or
        // search inside an unrelated payload for a coincidental DID byte sequence.
        guard let payload = ISO15765Parser().assembleISOTPPayloads(rawResponse)
            .first(where: { $0.ecu.uppercased() == expectedECU })?.payload,
              payload.hasPrefix("62" + command.dropFirst(2)),
              let bytes = payload.hexBytes(after: "62" + command.dropFirst(2), count: command == "222005" ? 1 : 2) else { return nil }

        if command == "222005" { return .aux12V(Double(bytes[0]) * 25.9 / 255) }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        switch command {
        case "222001": return .speed(Double(raw) * 0.05625) // Front-left wheel
        case "226050": return raw <= 10_000 ? .soc(Double(raw) / 100) : nil
        case "226075": return .packVoltage(Double(raw) * 0.025)
        case "226053": return .packCurrent(Double(Int16(bitPattern: raw)) / 10)
        case "222526": return .coolantTemp(Double(Int16(bitPattern: raw)) * 0.125)
        default: return nil
        }
    }
}
