import Foundation

/// One fault-memory record read with UDS service `0x19` (ReadDTCInformation).
///
/// A UDS fault is three bytes: the two-byte SAE J2012 code plus a failure-type byte.
/// Mercedes-Benz prints exactly that record in its own bulletins — `P154B00` is
/// `15 4B 00`, `B183301` is `98 33 01` — so rendering the three bytes is enough to
/// reproduce a Mercedes identifier without any proprietary table.
public struct UDSDiagnosticTroubleCode: Sendable, Hashable, Codable {
    /// SAE J2012 notation for the first two bytes, e.g. `P0DE6` or `B1833`.
    public let saeCode: String
    /// Third byte: what failed (short to ground, open circuit, internal failure, ...).
    public let failureType: UInt8
    /// ISO 14229 status byte as reported by the module.
    public let status: UInt8

    /// The identifier as a technician reads it, e.g. `B1833-01`.
    public var code: String { "\(saeCode)-\(String(format: "%02X", failureType))" }

    public init(saeCode: String, failureType: UInt8, status: UInt8) {
        self.saeCode = saeCode
        self.failureType = failureType
        self.status = status
    }
}

/// A module that stores its own fault memory behind UDS `19 02`.
///
/// UDS `19` is physical-addressed: each module needs its own request header and
/// answers on its own response header, unlike the functional Mode 03 broadcast.
public struct DiagnosticModule: Sendable, Hashable, Identifiable {
    public let name: String
    public let requestHeader: String
    public let responseHeader: String

    public var id: String { "\(requestHeader)->\(responseHeader)" }

    public init(name: String, requestHeader: String, responseHeader: String) {
        self.name = name
        self.requestHeader = requestHeader
        self.responseHeader = responseHeader
    }
}

public enum UDSDiagnostics {
    /// `reportDTCByStatusMask` with every status bit set. Some modules reject `FF`
    /// and only accept a narrower mask.
    public static let readDTCByStatusMask = "1902FF"
    /// Confirmed codes only; the fallback when a module rejects the `FF` mask.
    public static let readConfirmedDTCs = "190208"
    /// `reportSupportedDTC`; a positive answer proves the module implements `0x19`.
    public static let supportedDTCs = "190A"

    /// Decodes a `59 02 <availabilityMask> [3-byte DTC + status]...` payload.
    /// Returns `nil` for anything that is not a positive `19 02` response, and an
    /// empty array for a positive response that stores no faults.
    public static func codes(fromPayload payload: String) -> [UDSDiagnosticTroubleCode]? {
        let bytes = ISO15765Parser.hexBytes(payload)
        guard bytes.count >= 3, bytes[0] == 0x59, bytes[1] == 0x02 else { return nil }

        var records: [UDSDiagnosticTroubleCode] = []
        var index = 3  // skip the DTC status availability mask
        while index + 3 < bytes.count {
            let first = bytes[index]
            let second = bytes[index + 1]
            let failureType = bytes[index + 2]
            let status = bytes[index + 3]
            index += 4
            records.append(
                UDSDiagnosticTroubleCode(
                    saeCode: saeCode(first: first, second: second), failureType: failureType, status: status))
        }
        return records
    }

    /// The negative response code when the module answered `7F 19 xx`, else `nil`.
    public static func negativeResponseCode(fromPayload payload: String) -> UInt8? {
        let bytes = ISO15765Parser.hexBytes(payload)
        guard bytes.count >= 3, bytes[0] == 0x7F, bytes[1] == 0x19 else { return nil }
        return bytes[2]
    }

    /// Two-byte SAE notation: bits 7-6 pick the letter, the rest are the four digits.
    public static func saeCode(first: UInt8, second: UInt8) -> String {
        let letter: String
        switch (first & 0xC0) >> 6 {
        case 0: letter = "P"
        case 1: letter = "C"
        case 2: letter = "B"
        default: letter = "U"
        }
        let digits = Int(first & 0x3F) << 8 | Int(second)
        return letter + String(format: "%04X", digits)
    }

    /// Text for the ISO 14229 / SAE J2012 failure-type byte. Only the values defined by
    /// the standard are translated; Mercedes uses its own high values (`FA`, `FC`, ...),
    /// which stay visibly manufacturer-defined instead of being guessed.
    public static func failureTypeDescription(_ failureType: UInt8) -> String {
        switch failureType {
        case 0x00: return "No sub-type information"
        case 0x01: return "General electrical failure"
        case 0x02: return "General signal failure"
        case 0x04: return "System internal failure"
        case 0x08: return "System programming failure"
        case 0x09: return "Algorithm-based failure"
        case 0x0A: return "Calibration or software failure"
        case 0x11: return "Circuit short to ground"
        case 0x12: return "Circuit short to battery"
        case 0x13: return "Circuit open"
        case 0x1C: return "Component internal failure"
        case 0x51: return "Not programmed"
        case 0x92: return "Performance or incorrect operation"
        default:
            return String(format: "Manufacturer-defined sub-type 0x%02X", failureType)
        }
    }

    /// Names of the status bits that are set, in bit order.
    public static func statusDescriptions(_ status: UInt8) -> [String] {
        let bits = [
            "Test failed", "Failed this operation cycle", "Pending", "Confirmed",
            "Not completed since last clear", "Failed since last clear",
            "Not completed this operation cycle", "Warning lamp requested",
        ]
        let set = bits.enumerated().compactMap { status & (1 << UInt8($0.offset)) == 0 ? nil : $0.element }
        return set.isEmpty ? ["No status flags set"] : set
    }
}
