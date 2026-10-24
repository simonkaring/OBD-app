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
///
/// Drive-unit temperatures and machine rpm/torque come from the sibling EQB signalset
/// (`OBDb/Mercedes-Benz-EQB`, signalsets/v3/default.json, CC BY-SA 4.0) on the same ECUs.
/// They are community definitions not yet confirmed on an EQA: a DID the car does not
/// answer simply never becomes a live metric, and implausible values are discarded by
/// `TelemetryPlausibility`. Verify each against the vehicle before treating it as measured.
public struct MercedesEQAOBDbProfile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (OBDb community)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh = 66.5
    public let estimatedFullRangeKm: Double? = 426.0

    public static let sourceURL = URL(string: "https://github.com/OBDb/Mercedes-Benz-EQA/blob/main/signalsets/v3/default.json")!
    public static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!

    public init() {}

    public var initializationCommands: [String] {
        [
            "AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT CAF 1",
            "AT SP 6", "AT ST FF", "AT CFC 1", "AT FCSM 0",
            "AT CRA 7ED", "AT SH 7E5",
        ]
    }

    public var pollingCommands: [String] {
        // Poll wheel speed first so pack-current charging inference has a stationary reading.
        [
            "AT CRA 7EA", "AT SH 7E2", "222001", "222002",
            "AT CRA 7ED", "AT SH 7E5", "226050", "226075", "226053", "222005", "222526", "226502", "226071", "226504",
            "222525",  // Drive-unit (power electric unit) temperature; EQB community definition
            "AT CRA 5A4", "AT SH 624", "220201",
            "220200", "220205", "220207",  // Electric machine temperatures, rpm and torque; EQB community definitions
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        Set([.soc, .packVoltage, .packCurrent, .power, .speed, .aux12V, .coolantTemp, .vehicleRange, .motorRpm, .motorTorque])
            .union(TelemetryMetric.eqaCommunityMetrics)
    }

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let command = command.replacingOccurrences(of: " ", with: "").uppercased()
        if ["222002", "226071", "226504", "220201", "222525", "220200", "220205", "220207"].contains(command) {
            return parseResponses(command: command, rawResponse: rawResponse).first
        }
        guard ["222001", "226050", "226075", "226053", "222005", "222526", "226502"].contains(command) else { return nil }
        let expectedECU = command == "222001" ? "7EA" : "7ED"
        // Headers are required by this profile. Never decode another ECU's reply or
        // search inside an unrelated payload for a coincidental DID byte sequence.
        guard
            let payload = ISO15765Parser().assembleISOTPPayloads(rawResponse)
                .first(where: { $0.ecu.uppercased() == expectedECU })?.payload,
            payload.hasPrefix("62" + command.dropFirst(2)),
            let bytes = payload.hexBytes(after: "62" + command.dropFirst(2), count: command == "226502" ? 4 : (command == "222005" ? 1 : 2))
        else { return nil }

        if command == "226502" {
            // Community definition; validate against the dashboard on the real vehicle.
            let km = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return km <= 1_000 ? .vehicleRange(Double(km)) : nil
        }
        if command == "222005" { return .aux12V(Double(bytes[0]) * 25.9 / 255) }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        switch command {
        case "222001": return .speed(Double(raw) * 0.05625)  // Front-left wheel
        case "226050": return raw <= 10_000 ? .soc(Double(raw) / 100) : nil
        case "226075": return .packVoltage(Double(raw) * 0.025)
        case "226053": return .packCurrent(-Double(Int16(bitPattern: raw)) / 10)
        case "222526": return .coolantTemp(Double(Int16(bitPattern: raw)) * 0.125)
        default: return nil
        }
    }

    public func parseResponses(command: String, rawResponse: String) -> [TelemetryUpdate] {
        let command = command.replacingOccurrences(of: " ", with: "").uppercased()
        let ecu = ["220201", "220200", "220205", "220207"].contains(command) ? "5A4" : (command.hasPrefix("2220") ? "7EA" : "7ED")
        guard
            let payload = ISO15765Parser().assembleISOTPPayloads(rawResponse)
                .first(where: { $0.ecu.uppercased() == ecu })?.payload,
            payload.hasPrefix("62" + command.dropFirst(2))
        else { return [] }
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
            for (index, name) in [
                TelemetryMetric.frontLeftWheelSpeed, .frontRightWheelSpeed,
                .rearLeftWheelSpeed, .rearRightWheelSpeed,
            ].enumerated() {
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
        case "222525": return metric(.driveUnitTemp, word(0, signed: true).map { $0 / 8 })
        case "220200":
            // Rotor, coolant, stator 1 and stator 2, each °C at (raw / 10) - 40. Report the
            // hottest sensor: that is the number that limits drive-unit power.
            guard bytes.count >= 10 else { return [] }
            let temperatures = [word(2, signed: true), word(4, signed: true), word(6, signed: true), word(8, signed: true)]
                .compactMap { $0 }
                .map { $0 / 10 - 40 }
            return metric(.motorTemp, temperatures.max())
        case "220205":
            // Electric machine rpm: machine 2 at bytes 2-3, machine 1 at bytes 10-11. The
            // single-motor EQA answers in only one of them, so prefer a turning machine.
            let machine1 = bytes.count >= 12 ? word(10) : nil
            let machine2 = word(2)
            return (machine1.flatMap { $0 > 0 ? $0 : nil } ?? machine2).map { [.motorRpm($0)] } ?? []
        case "220207":
            // Electric machine actual torque, Nm at (raw / 10) - 500.
            return word(0).map { [.motorTorque($0 / 10 - 500)] } ?? []
        default: return parseResponse(command: command, rawResponse: rawResponse).map { [$0] } ?? []
        }
    }
}
