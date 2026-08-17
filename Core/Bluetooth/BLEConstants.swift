import Foundation
import CoreBluetooth

public enum BLEConstants {
    // Vgate iCar Pro 2S & iOS-Vlink standard BLE GATT Profile (18F0)
    public static let vgateServiceUUID = CBUUID(string: "000018F0-0000-1000-8000-00805F9B34FB")
    public static let vgateShortServiceUUID = CBUUID(string: "18F0")
    public static let vgateWriteCharUUID = CBUUID(string: "00002AF1-0000-1000-8000-00805F9B34FB")
    public static let vgateNotifyCharUUID = CBUUID(string: "00002AF0-0000-1000-8000-00805F9B34FB")

    // Vgate vLinker / ios-vlink 128-bit Custom GATT Profile
    public static let vgate128ServiceUUID = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    public static let vgate128CharUUID = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")

    // HM-10 / CC2541 / Generic ELM327 BLE (FFE0)
    public static let hm10ServiceUUID = CBUUID(string: "FFE0")
    public static let hm10LongServiceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    public static let hm10CharUUID = CBUUID(string: "FFE1")
    public static let hm10LongCharUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")

    // Veepeak / Generic ELM327 Custom GATT Services (FFF0)
    public static let genericUARTService = CBUUID(string: "FFF0")
    public static let genericUARTLongService = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
    public static let genericUARTWrite = CBUUID(string: "FFF2")
    public static let genericUARTNotify = CBUUID(string: "FFF1")

    // Nordic UART Service (NUS)
    public static let nordicUARTService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let nordicUARTWrite = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let nordicUARTNotify = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // Microchip / ISSC BLE Profile
    public static let isscServiceUUID = CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFF207E245")
    public static let isscWriteCharUUID = CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3")
    public static let isscNotifyCharUUID = CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616")

    public static let allSupportedServices = [
        vgateServiceUUID,
        vgateShortServiceUUID,
        vgate128ServiceUUID,
        hm10ServiceUUID,
        hm10LongServiceUUID,
        genericUARTService,
        genericUARTLongService,
        nordicUARTService,
        isscServiceUUID
    ]

    public static let knownWriteCharacteristics: Set<CBUUID> = [
        vgateWriteCharUUID,
        vgate128CharUUID,
        hm10CharUUID,
        hm10LongCharUUID,
        genericUARTWrite,
        nordicUARTWrite,
        isscWriteCharUUID
    ]

    public static let knownNotifyCharacteristics: Set<CBUUID> = [
        vgateNotifyCharUUID,
        vgate128CharUUID,
        hm10CharUUID,
        hm10LongCharUUID,
        genericUARTNotify,
        nordicUARTNotify,
        isscNotifyCharUUID
    ]

    // Standard BLE SIG informational services that should not be used as UART communication channels
    public static let ignoredStandardServices: Set<CBUUID> = [
        CBUUID(string: "1800"), // Generic Access
        CBUUID(string: "1801"), // Generic Attribute
        CBUUID(string: "180A"), // Device Information
        CBUUID(string: "180F")  // Battery Service
    ]

    public static let defaultTimeout: TimeInterval = 4.0
    public static let connectionTimeout: TimeInterval = 10.0

    // Grace period after a command timeout before dispatching the next command,
    // so a late/stale BLE notification for the timed-out command drains and gets
    // discarded instead of being merged into the next command's response buffer.
    public static let staleResponseDrainDelay: TimeInterval = 0.3
}

public enum BLEConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(deviceName: String)
    case ready(deviceName: String)
    case demoMode
    case error(String)

    public var isConnected: Bool {
        switch self {
        case .ready, .demoMode:
            return true
        default:
            return false
        }
    }
}
