import Foundation

/// Adapted from OBDb/Mercedes-Benz-EQA contributors, signalsets/v3/default.json
/// (retrieved 2026-09-13). This adaptation is licensed CC BY-SA 4.0:
/// https://creativecommons.org/licenses/by-sa/4.0/
/// Source: https://github.com/OBDb/Mercedes-Benz-EQA/blob/main/signalsets/v3/default.json
/// Provided as-is, without warranties; see Section 5 of the license.
/// Changes: Swift decoding of a telemetry subset, explicit ELM routing, current-sign
/// normalization and SOC validation. Other physical bounds are enforced by the telemetry
/// manager instead of upstream display maxima (which cap HV voltage at 100 V).
/// Upstream marks these commands dbg:true. The 2026-09-13 EQA drive capture confirms
/// negative ECU current during discharge; VoltLink uses negative for energy entering the pack.
public struct MercedesEQAOBDbProfile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (OBDb community)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh = 66.5
    public let estimatedFullRangeKm: Double? = 426.0

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
        ["AT CRA 7EA", "AT SH 7E2", "222001", "222002",
         "AT CRA 7ED", "AT SH 7E5", "226050", "226075", "226053", "222005", "222526", "226502", "226071", "226504",
         "AT CRA 5A4", "AT SH 624", "220201"]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        Set([.soc, .packVoltage, .packCurrent, .power, .speed, .aux12V, .coolantTemp, .vehicleRange])
            .union(TelemetryMetric.eqaCommunityMetrics)
    }

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let command = command.replacingOccurrences(of: " ", with: "").uppercased()
        if ["222002", "226071", "226504", "220201"].contains(command) {
            return parseResponses(command: command, rawResponse: rawResponse).first
        }
        guard ["222001", "226050", "226075", "226053", "222005", "222526", "226502"].contains(command) else { return nil }
        let expectedECU = command == "222001" ? "7EA" : "7ED"
        // Headers are required by this profile. Never decode another ECU's reply or
        // search inside an unrelated payload for a coincidental DID byte sequence.
        guard let payload = ISO15765Parser().assembleISOTPPayloads(rawResponse)
            .first(where: { $0.ecu.uppercased() == expectedECU })?.payload,
              payload.hasPrefix("62" + command.dropFirst(2)),
               let bytes = payload.hexBytes(after: "62" + command.dropFirst(2), count: command == "226502" ? 4 : (command == "222005" ? 1 : 2)) else { return nil }

        if command == "226502" {
            // Community definition; validate against the dashboard on the real vehicle.
            let km = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return km <= 1_000 ? .vehicleRange(Double(km)) : nil
        }
        if command == "222005" { return .aux12V(Double(bytes[0]) * 25.9 / 255) }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        switch command {
        case "222001": return .speed(Double(raw) * 0.05625) // Front-left wheel
        case "226050": return raw <= 10_000 ? .soc(Double(raw) / 100) : nil
        case "226075": return .packVoltage(Double(raw) * 0.025)
        case "226053": return .packCurrent(-Double(Int16(bitPattern: raw)) / 10)
        case "222526": return .coolantTemp(Double(Int16(bitPattern: raw)) * 0.125)
        default: return nil
        }
    }

    public func parseResponses(command: String, rawResponse: String) -> [TelemetryUpdate] {
        let command = command.replacingOccurrences(of: " ", with: "").uppercased()
        let ecu = command == "220201" ? "5A4" : (command.hasPrefix("2220") ? "7EA" : "7ED")
        guard let payload = ISO15765Parser().assembleISOTPPayloads(rawResponse)
            .first(where: { $0.ecu.uppercased() == ecu })?.payload,
              payload.hasPrefix("62" + command.dropFirst(2)) else { return [] }
        // Read the whole ISO-TP reply: several published signals share one DID.
        guard let bytes = payload.hexBytes(after: "62" + command.dropFirst(2)) else { return [] }
        func word(_ index: Int, signed: Bool = false) -> Double? {
            guard bytes.count >= index + 2 else { return nil }
            let bits = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            return signed ? Double(Int16(bitPattern: bits)) : Double(bits)
        }
        func metric(_ name: TelemetryMetric, _ value: Double?) -> [TelemetryUpdate] {
            value.map { [.communityMetric(name, $0)] } ?? []
        }
        switch command {
        case "222001":
            var result = parseResponse(command: command, rawResponse: rawResponse).map { [$0] } ?? []
            for (index, name) in [TelemetryMetric.frontLeftWheelSpeed, .frontRightWheelSpeed,
                                  .rearLeftWheelSpeed, .rearRightWheelSpeed].enumerated() {
                result += metric(name, word(index * 2).map { $0 * 0.05625 })
            }
            return result
        case "222002":
            return metric(.longitudinalAcceleration, word(1, signed: true).map { $0 * 0.00005 })
                + metric(.lateralAcceleration, word(3, signed: true).map { $0 * 0.015625 })
                + metric(.yawRate, word(6, signed: true).map { $0 * 0.003497 })
                + metric(.steeringAngle, word(9, signed: true).map { $0 * 0.1 })
                + metric(.brakeCylinderPressure, word(12, signed: true).map { $0 * 0.0153 })
                + metric(.vacuumBrakePressure, word(18).map { $0 / 1000 })
        case "226071": return metric(.converterRequestedVoltage, word(0).map { $0 * 0.025 })
        case "226504": return metric(.serviceDistance, word(0))
        case "220201": return metric(.aux12VHighDefinition, word(2).map { $0 * 0.1 })
        default: return parseResponse(command: command, rawResponse: rawResponse).map { [$0] } ?? []
        }
    }
}
