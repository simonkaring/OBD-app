import Foundation
import CoreBluetooth
import Combine

public struct OBDLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let sent: String
    public let response: String
}

public final class BluetoothManager: NSObject, ObservableObject, OBDConnectionProtocol {
    @Published public private(set) var state: BLEConnectionState = .disconnected
    @Published public private(set) var discoveredDevices: [CBPeripheral] = []
    @Published public private(set) var log: [OBDLogEntry] = []

    public weak var delegate: OBDConnectionDelegate?

    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var boundService: CBService?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var notifyConfirmed = false
    private var didRetryServiceDiscovery = false

    private var buffer = ""

    private struct QueuedCommand {
        let command: String
        let completion: ((Result<String, Error>) -> Void)?
        let timeout: TimeInterval
    }
    private var commandQueue: [QueuedCommand] = []
    private var inFlightCommand: QueuedCommand?
    private var commandTimer: Timer?

    private static let maxLogEntries = 500

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    public func connect(peripheralName: String? = nil) {
        state = .scanning
        discoveredDevices.removeAll()
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    public func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        activePeripheral = peripheral
        peripheral.delegate = self
        let name = peripheral.name ?? "OBD Adapter"
        state = .connecting(deviceName: name)
        delegate?.obdConnectionStateDidChange(state)
        centralManager.connect(peripheral, options: nil)
    }

    public func disconnect() {
        if let peripheral = activePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
        state = .disconnected
        delegate?.obdConnectionStateDidChange(.disconnected)
    }

    private func resetConnectionState() {
        activePeripheral = nil
        boundService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notifyConfirmed = false
        didRetryServiceDiscovery = false
        buffer = ""
        commandTimer?.invalidate()
        commandTimer = nil
        let failedQueue = commandQueue
        let failedInFlight = inFlightCommand
        commandQueue.removeAll()
        inFlightCommand = nil
        let error = NSError(domain: "BluetoothManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Disconnected"])
        failedInFlight?.completion?(.failure(error))
        failedQueue.forEach { $0.completion?(.failure(error)) }
    }

    public func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        guard state.isConnected else {
            completion?(.failure(NSError(domain: "BluetoothManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "BLE Not connected"])))
            return
        }

        let timeout = command.uppercased().hasPrefix("AT Z") ? BLEConstants.defaultTimeout * 1.5 : BLEConstants.defaultTimeout
        commandQueue.append(QueuedCommand(command: command, completion: completion, timeout: timeout))
        dispatchNextCommandIfIdle()
    }

    private func dispatchNextCommandIfIdle() {
        guard inFlightCommand == nil, !commandQueue.isEmpty else { return }
        guard let peripheral = activePeripheral, let writeChar = writeCharacteristic else {
            let queued = commandQueue.removeFirst()
            queued.completion?(.failure(NSError(domain: "BluetoothManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "BLE Not connected"])))
            dispatchNextCommandIfIdle()
            return
        }

        let next = commandQueue.removeFirst()
        inFlightCommand = next
        buffer = ""

        let payload = next.command + "\r"
        guard let data = payload.data(using: .utf8) else {
            completeInFlight(.failure(NSError(domain: "BluetoothManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Bad command encoding"])), rawResponse: nil)
            return
        }

        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: writeChar, type: writeType)

        commandTimer?.invalidate()
        commandTimer = Timer.scheduledTimer(withTimeInterval: next.timeout, repeats: false) { [weak self] _ in
            self?.completeInFlight(.failure(NSError(domain: "BluetoothManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Command Timeout"])), rawResponse: nil)
        }
    }

    private func completeInFlight(_ result: Result<String, Error>, rawResponse: String?) {
        commandTimer?.invalidate()
        commandTimer = nil
        guard let completed = inFlightCommand else { return }
        inFlightCommand = nil

        let responseText: String
        switch result {
        case .success(let raw): responseText = raw
        case .failure(let err): responseText = "ERROR: \(err.localizedDescription)"
        }
        appendLog(sent: completed.command, response: responseText)

        completed.completion?(result)
        if case .success(let raw) = result {
            delegate?.obdConnectionDidReceiveResponse(command: completed.command, rawResponse: raw)
        }

        dispatchNextCommandIfIdle()
    }

    private func appendLog(sent: String, response: String) {
        log.append(OBDLogEntry(timestamp: Date(), sent: sent, response: response))
        if log.count > Self.maxLogEntries {
            log.removeFirst(log.count - Self.maxLogEntries)
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if case .scanning = state {
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        } else {
            state = .error("Bluetooth is off or unauthorized")
            delegate?.obdConnectionStateDidChange(state)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }

        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let matchesKnownService = !Set(advertisedServices).isDisjoint(with: Set(BLEConstants.allSupportedServices))
        let matchesName = name.contains("Vlink") || name.contains("iCar") || name.contains("OBD") || name.contains("BLE") || name.contains("VEEPEAK")

        if matchesKnownService || matchesName {
            central.stopScan()
            activePeripheral = peripheral
            peripheral.delegate = self
            state = .connecting(deviceName: name.isEmpty ? "OBD Adapter" : name)
            delegate?.obdConnectionStateDidChange(state)
            central.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        didRetryServiceDiscovery = false
        peripheral.discoverServices(BLEConstants.allSupportedServices)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetConnectionState()
        state = .disconnected
        delegate?.obdConnectionStateDidChange(state)
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let knownServices = (peripheral.services ?? []).filter { BLEConstants.allSupportedServices.contains($0.uuid) }

        if knownServices.isEmpty {
            if !didRetryServiceDiscovery {
                didRetryServiceDiscovery = true
                peripheral.discoverServices(nil)
            }
            return
        }

        for service in knownServices {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard boundService == nil else { return }
        guard BLEConstants.allSupportedServices.contains(service.uuid) else { return }
        guard let characteristics = service.characteristics else { return }

        let knownWriteUUIDs: Set<CBUUID> = [BLEConstants.vgateWriteCharUUID, BLEConstants.genericUARTWrite, BLEConstants.isscWriteCharUUID]
        let knownNotifyUUIDs: Set<CBUUID> = [BLEConstants.vgateNotifyCharUUID, BLEConstants.genericUARTNotify, BLEConstants.isscNotifyCharUUID]

        var write = characteristics.first { knownWriteUUIDs.contains($0.uuid) }
        var notify = characteristics.first { knownNotifyUUIDs.contains($0.uuid) }

        if write == nil {
            write = characteristics.first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
        }
        if notify == nil {
            notify = characteristics.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        }

        guard let writeChar = write, let notifyChar = notify else { return }

        boundService = service
        writeCharacteristic = writeChar
        notifyCharacteristic = notifyChar
        peripheral.setNotifyValue(true, for: notifyChar)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic === notifyCharacteristic, error == nil, characteristic.isNotifying else { return }
        notifyConfirmed = true
        let devName = peripheral.name ?? "OBD Adapter"
        state = .ready(deviceName: devName)
        delegate?.obdConnectionStateDidChange(state)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let str = String(data: data, encoding: .utf8) else { return }
        buffer += str

        if buffer.contains(">") {
            let responseStr = buffer
            buffer = ""
            completeInFlight(.success(responseStr), rawResponse: responseStr)
        }
    }
}
