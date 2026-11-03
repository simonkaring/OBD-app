import Foundation

/// One SAE J1979 Mode 02 ("freeze frame") signal: the conditions an ECU recorded at the
/// moment it stored a fault code.
///
/// Only the small, widely supported set below is queried. Adapters without Mode 02 support,
/// and ECUs that do not store a frame, simply return no data and the signal is skipped rather
/// than surfacing an error alongside an otherwise successful scan.
public enum FreezeFrameSignal: String, CaseIterable, Sendable {
    case engineLoad
    case coolantTemp
    case rpm
    case speed
    case intakeAirTemp
    case throttlePosition
    case fuelLevel
    case controlModuleVoltage

    public var pid: UInt8 {
        switch self {
        case .engineLoad: return 0x04
        case .coolantTemp: return 0x05
        case .rpm: return 0x0C
        case .speed: return 0x0D
        case .intakeAirTemp: return 0x0F
        case .throttlePosition: return 0x11
        case .fuelLevel: return 0x2F
        case .controlModuleVoltage: return 0x42
        }
    }

    public var label: String {
        switch self {
        case .engineLoad: return "Engine load"
        case .coolantTemp: return "Coolant"
        case .rpm: return "Engine speed"
        case .speed: return "Vehicle speed"
        case .intakeAirTemp: return "Intake air"
        case .throttlePosition: return "Throttle"
        case .fuelLevel: return "Fuel / charge level"
        case .controlModuleVoltage: return "Module voltage"
        }
    }

    public var unit: String? {
        switch self {
        case .engineLoad, .throttlePosition, .fuelLevel: return "%"
        case .coolantTemp, .intakeAirTemp: return "°C"
        case .rpm: return "rpm"
        case .speed: return "km/h"
        case .controlModuleVoltage: return "V"
        }
    }

    /// The Mode 02 request for frame 0, e.g. `020D00` for vehicle speed.
    public var command: String {
        String(format: "02%02X00", pid)
    }

    /// Number of data bytes the PID carries in its Mode 02 payload.
    var byteCount: Int {
        switch self {
        case .rpm, .controlModuleVoltage: return 2
        default: return 1
        }
    }

    /// Decodes one frame using the SAE J1979 scaling for the PID.
    public func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= byteCount else { return nil }
        let a = Double(bytes[0])
        let b = byteCount > 1 ? Double(bytes[1]) : 0
        switch self {
        case .engineLoad, .throttlePosition, .fuelLevel:
            return a * 100.0 / 255.0
        case .coolantTemp, .intakeAirTemp:
            return a - 40.0
        case .rpm:
            return ((a * 256.0) + b) / 4.0
        case .speed:
            return a
        case .controlModuleVoltage:
            return ((a * 256.0) + b) / 1000.0
        }
    }

    /// Renders a decoded value for the diagnostic sheet, e.g. `"42 km/h"`.
    public func display(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let decimals = self == .controlModuleVoltage ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(decimals)))
        guard let unit else { return number }
        return "\(number) \(unit)"
    }

    /// Extracts this signal from a raw ELM327 Mode 02 response. Returns nil when the ECU
    /// answered with a negative response, `NO DATA`, or a frame other than frame 0.
    public func parse(rawResponse: String) -> Double? {
        for frame in ISO15765Parser().assembleISOTPPayloads(rawResponse) {
            let bytes = Self.hexBytes(frame.payload)
            guard bytes.count >= 3 + byteCount,
                bytes[0] == 0x42,
                bytes[1] == pid,
                bytes[2] == 0x00
            else { continue }
            return decode(Array(bytes[3..<(3 + byteCount)]))
        }
        return nil
    }

    /// Frame values in the stable order the UI renders, labelled by signal.
    public static func orderedValues(from frames: [String: String]) -> [(label: String, value: String)] {
        allCases.compactMap { signal in
            frames[signal.label].map { (label: signal.label, value: $0) }
        }
    }

    private static func hexBytes(_ hex: String) -> [UInt8] {
        ISO15765Parser.hexBytes(hex)
    }
}
