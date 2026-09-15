import Foundation

public struct MercedesEQA250Profile: VehicleProfile {
    public let vehicleName = "Mercedes-Benz EQA 250 (2021)"
    public let isElectricVehicle = true
    public let batteryUsableCapacityKWh: Double = 66.5
    public let grossCapacityKWh: Double = 69.7
    /// WLTP-rated full-charge range, conservative rounding.
    public let estimatedFullRangeKm: Double? = 426.0
    public let retainUnverifiedPollingCommands: Bool = true

    private let isoParser = ISO15765Parser()

    public var initializationCommands: [String] {
        [
            "AT Z",            // Reset ELM327
            "AT E0",           // Echo Off
            "AT L0",           // Linefeed Off
            "AT S1",           // Spaces On (required by the space-delimited ISO-TP token parser)
            "AT H1",           // Headers On (for CAN ID recognition)
            "AT CAF 1",        // CAN Auto Formatting
            "AT SP 7",         // Force ISO 15765-4 CAN (29-bit ID, 500 kbps)
            "AT CP 18",        // 29-bit CAN Priority
            "AT ST FF",        // ELM response timeout ~1.02s
            "ATCRA 18DAF159",  // CAN Receive filter for BMS
            "AT SH 18DA59F1",  // Physical addressing: tester (F1) -> BMS ECU (0x59)
            "AT FCSH 18DA59F1",
            "AT FCSD 300000",
            "AT FCSM 1"
        ]
    }

    public var pollingCommands: [String] {
        [
            "ATCRA 18DAF159",
            "AT SH 18DA59F1",
            "22010A",         // BMS pack voltage (0.1V resolution)
            "220210"          // Raw capture only; DID meaning/scaling unverified
        ]
    }

    public var supportedMetrics: Set<TelemetryMetric> {
        [.packVoltage]
    }

    public init() {}

    public func parseResponse(command: String, rawResponse: String) -> TelemetryUpdate? {
        let cleanHex = isoParser.assembleISOTPPayload(rawResponse)
        
        switch command {
        case "22010A", "22 01 0A": // BMS pack voltage (ECU 0x59)
            if let bytes = cleanHex.hexBytes(after: "62010A", count: 2) {
                let voltage = (Double(bytes[0]) * 256.0 + Double(bytes[1])) * 0.1
                return .packVoltage(voltage)
            }
            return nil

        case "220210", "22 02 10":
            // 2026-09-06 18:58-18:59 UTC: dashboard 81%, but raw / 250 / 66.5 * 100
            // yielded ~96.6%. A match at full charge did not validate this as SOC.
            return nil

        default:
            return nil
        }
    }
}
