import Foundation
import CoreBluetooth
import Combine

public final class BluetoothManager: NSObject, ObservableObject, OBDConnectionProtocol {
    @Published public private(set) var state: BLEConnectionState = .disconnected
    @Published public private(set) var discoveredDevices: [CBPeripheral] = []

    public weak var delegate: OBDConnectionDelegate?

    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var buffer = ""
    private var pendingCompletion: ((Result<String, Error>) -> Void)?
    private var commandTimer: Timer?

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    public func connect(peripheralName: String? = nil) {
        state = .scanning
        discoveredDevices.removeAll()
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: BLEConstants.allSupportedServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    public func disconnect() {
        if let peripheral = activePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        activePeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        state = .disconnected
        delegate?.obdConnectionStateDidChange(.disconnected)
    }

    public func sendCommand(_ command: String, completion: ((Result<String, Error>) -> Void)?) {
        guard state.isConnected, let peripheral = activePeripheral, let writeChar = writeCharacteristic else {
            completion?(.failure(NSError(domain: "BluetoothManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "BLE Not connected"])))
            return
        }

        self.pendingCompletion = completion
        self.buffer = ""

        let payload = command + "\r"
        guard let data = payload.data(using: .utf8) else { return }

        peripheral.writeValue(data, for: writeChar, type: .withResponse)

        commandTimer?.invalidate()
        commandTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.defaultTimeout, repeats: false) { [weak self] _ in
            if let completion = self?.pendingCompletion {
                self?.pendingCompletion = nil
                completion(.failure(NSError(domain: "BluetoothManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Command Timeout"])))
            }
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if case .scanning = state {
                central.scanForPeripherals(withServices: BLEConstants.allSupportedServices, options: nil)
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
        if name.contains("Vlink") || name.contains("iCar") || name.contains("OBD") {
            central.stopScan()
            activePeripheral = peripheral
            peripheral.delegate = self
            state = .connecting(deviceName: name)
            delegate?.obdConnectionStateDidChange(state)
            central.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(BLEConstants.allSupportedServices)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        delegate?.obdConnectionStateDidChange(state)
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = char
            }
            if char.properties.contains(.notify) || char.properties.contains(.read) {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        if writeCharacteristic != nil && notifyCharacteristic != nil {
            let devName = peripheral.name ?? "iCar Pro 2S"
            state = .ready(deviceName: devName)
            delegate?.obdConnectionStateDidChange(state)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let str = String(data: data, encoding: .utf8) else { return }
        buffer += str

        if buffer.contains(">") {
            commandTimer?.invalidate()
            let responseStr = buffer
            buffer = ""
            let completion = pendingCompletion
            pendingCompletion = nil
            completion?(.success(responseStr))
            delegate?.obdConnectionDidReceiveResponse(command: "", rawResponse: responseStr)
        }
    }
}
