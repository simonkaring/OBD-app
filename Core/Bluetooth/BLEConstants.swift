import Foundation
import CoreBluetooth

public enum BLEConstants {
    // Vgate iCar Pro 2S & iOS-Vlink standard BLE GATT Profile
    public static let vgateServiceUUID = CBUUID(string: "000018F0-0000-1000-8000-00805F9B34FB")
    public static let vgateWriteCharUUID = CBUUID(string: "00002AF1-0000-1000-8000-00805F9B34FB")
    public static let vgateNotifyCharUUID = CBUUID(string: "00002AF0-0000-1000-8000-00805F9B34FB")

    // Veepeak / Generic ELM327 Custom GATT Services
    public static let genericUARTService = CBUUID(string: "FFF0")
    public static let genericUARTWrite = CBUUID(string: "FFF2")
    public static let genericUARTNotify = CBUUID(string: "FFF1")

    // Microchip / ISSC BLE Profile
    public static let isscServiceUUID = CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFF207E245")
    public static let isscWriteCharUUID = CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3")
    public static let isscNotifyCharUUID = CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616")

    public static let allSupportedServices = [
        vgateServiceUUID,
        genericUARTService,
        isscServiceUUID
    ]

    public static let defaultTimeout: TimeInterval = 4.0

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
