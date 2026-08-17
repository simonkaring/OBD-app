import Foundation

public struct MercedesEQA250Profile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (2021)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 66.5
    public let grossCapacityKWh: Double = 69.7

    private let isoParser = ISO15765Parser()

    // Confirmed against a real EQA via direct BLE probing (see scratch/bus_probe.swift):
    // the diagnostic gateway uses 29-bit extended CAN addressing (ISO 15765-4 CAN 29/500,
    // protocol 7), not the 11-bit protocol 6 originally assumed. AT SP 6 / 7E0 / 7E4
    // headers get no useful UDS responses on this car; SAE J1979 Mode 01 (010D etc.) is
    // also a dead end on a BEV, which has no emissions system to report on.
    //
    // Physical addressing (tester F1 -> ECU) reaches two distinct nodes:
    //   0x59 (header 18DA59F1) answers DID 010A with pack voltage (~0.1 V/bit)
    //   0x29 (header 18DA29F1) answers DID 012F with an SOC-like value (~0.1 %/bit,
    //     read ~3-4 points below the dash display — consistent with a raw BMS SOC vs.
    //     the dash's rescaled "customer SOC", a common EV discrepancy)
    // SOH, battery temp, 12V aux, and motor stats DIDs are not yet identified.
    public var initializationCommands: [String] {
        [
            "AT Z",       // Reset ELM327
            "AT E0",      // Echo Off
            "AT L0",      // Linefeed Off
            "AT S1",      // Spaces On (required by the space-delimited ISO-TP token parser)
            "AT H1",      // Headers On (for CAN ID recognition)
            "AT CAF 1",   // CAN Auto Formatting
            "AT SP 7",    // Force ISO 15765-4 CAN (29-bit ID, 500 kbps)
            "AT ST FF",   // ELM response timeout ~1.02s — default (~200ms) is too short for UDS 22xx replies through the gateway
            "AT DP",      // Report negotiated protocol (visible in the OBD log)
            "AT AL",      // Allow Long messages
            "AT SH 18DA59F1" // Physical addressing: tester (F1) -> pack voltage ECU (0x59)
        ]
    }

    public var pollingCommands: [String] {
        [
            "AT SH 18DA59F1", // Physical addressing -> pack voltage ECU (0x59)
            "22010A",         // Pack Voltage
            "AT SH 18DA29F1", // Physical addressing -> SOC ECU (0x29)
            "22012F"          // State of Charge
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.soc, .packVoltage]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let cleanHex = isoParser.assembleISOTPPayload(rawResponse)
        
        switch command {
        case "22010A": // Pack Voltage (ECU 0x59)
            guard let bytes = extractBytes(from: cleanHex, header: "62010A", count: 2) else { return nil }
            let voltage = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
            return .packVoltage(voltage)

        case "22012F": // State of Charge (ECU 0x29)
            guard let bytes = extractBytes(from: cleanHex, header: "62012F", count: 2) else { return nil }
            let soc = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
            return .soc(min(100.0, max(0.0, soc)))

        default:
            return nil
        }
    }

    private func extractBytes(from hex: String, header: String, count: Int) -> [UInt8]? {
        guard let range = hex.range(of: header) else { return nil }
        let afterHeader = String(hex[range.upperBound...])
        guard afterHeader.count >= count * 2 else { return nil }
        var bytes: [UInt8] = []
        for i in 0..<count {
            let start = afterHeader.index(afterHeader.startIndex, offsetBy: i * 2)
            let end = afterHeader.index(start, offsetBy: 2)
            let byteStr = String(afterHeader[start..<end])
            if let b = UInt8(byteStr, radix: 16) {
                bytes.append(b)
            }
        }
        return bytes.count == count ? bytes : nil
    }
}
