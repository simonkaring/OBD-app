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
    @Published public private(set) var isCapturing = false
    @Published public private(set) var captureFileURL: URL?
    @Published public private(set) var captureError: String?

    private var captureDestination = URL.documentsDirectory.appendingPathComponent("VoltLink-OBD-Capture.txt")
    private var captureHandle: FileHandle?
    private var openCaptureFile: (URL) throws -> FileHandle = { try FileHandle(forWritingTo: $0) }
    private static let captureDateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public weak var delegate: OBDConnectionDelegate?

    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var boundService: CBService?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
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
    private var connectionTimeoutTimer: Timer?
    private var isDraining = false
    private var recoveryGeneration = 0
    private var recoveryWorkItem: DispatchWorkItem?
    private var commandWriter: ((Data) -> Void)?
    private var scheduleRecovery: (DispatchWorkItem) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.staleResponseDrainDelay, execute: $0)
    }

    public static let maxLogEntries = 500

    public override init() {
        super.init()
        if FileManager.default.fileExists(atPath: captureDestination.path) {
            captureFileURL = captureDestination
        }
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // Exercise the command queue without creating a CoreBluetooth connection.
    init(
        commandWriter: @escaping (Data) -> Void,
        scheduleRecovery: @escaping (DispatchWorkItem) -> Void,
        captureDirectory: URL = .documentsDirectory,
        openCaptureFile: @escaping (URL) throws -> FileHandle = { try FileHandle(forWritingTo: $0) }
    ) {
        self.commandWriter = commandWriter
        self.scheduleRecovery = scheduleRecovery
        self.captureDestination = captureDirectory.appendingPathComponent("VoltLink-OBD-Capture.txt")
        self.openCaptureFile = openCaptureFile
        super.init()
        if FileManager.default.fileExists(atPath: captureDestination.path) {
            captureFileURL = captureDestination
        }
        state = .ready(deviceName: "Test Adapter")
    }

    deinit {
        do {
            try captureHandle?.close()
        } catch {
            NSLog("OBD capture close failed; file may be partial: %@", error.localizedDescription)
        }
    }

    @MainActor
    public func startCapture(vehicleContext: String) {
        guard !isCapturing else { return }
        captureError = nil
        let files = FileManager.default
        let directory = captureDestination.deletingLastPathComponent()
        let stagingURL = directory.appendingPathComponent(".OBD-Capture-\(UUID().uuidString).tmp")
        var handle: FileHandle?
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let header = """
            # VoltLink OBD diagnostic capture
            # Vehicle: \(vehicleContext)
            # Started: \(Date().formatted(Self.captureDateFormat))
            # Start-forward only; previous live history is not included.
            # Timestamps are command completion times (UTC, milliseconds).
            # Raw responses follow each TX line; original line endings are preserved.


            """
            // Prepare and flush the new file before touching the previous capture.
            try Data(header.utf8).write(to: stagingURL, options: .atomic)
            let opened = try openCaptureFile(stagingURL)
            handle = opened
            try opened.seekToEnd()
            try opened.synchronize()
            if files.fileExists(atPath: captureDestination.path) {
                _ = try files.replaceItemAt(captureDestination, withItemAt: stagingURL)
            } else {
                try files.moveItem(at: stagingURL, to: captureDestination)
            }
            captureHandle = opened
            captureFileURL = captureDestination
            isCapturing = true
        } catch {
            try? handle?.close()
            try? files.removeItem(at: stagingURL)
            captureError = "Could not start capture: \(error.localizedDescription)"
                + (captureFileURL == nil ? "" : " The previous capture is still available to export.")
        }
    }

    public func stopCapture() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let handle = captureHandle else { return }
        captureHandle = nil
        var failures: [String] = []
        do { try handle.synchronize() } catch { failures.append(error.localizedDescription) }
        do { try handle.close() } catch { failures.append(error.localizedDescription) }
        isCapturing = false
        if !failures.isEmpty {
            captureError = "Capture stopped: \(failures.joined(separator: "; ")). Export the capture file to recover partial data."
        }
    }

    @MainActor
    public func clearLog() {
        log.removeAll()
    }

    public func connect(peripheralName: String? = nil) {
        guard activePeripheral == nil else { return }
        state = .scanning
        discoveredDevices.removeAll()
        delegate?.obdConnectionStateDidChange(state)
        if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    public func connect(to peripheral: CBPeripheral) {
        guard peripheral !== activePeripheral else { return }
        if activePeripheral != nil { disconnect() }
        centralManager.stopScan()
        activePeripheral = peripheral
        peripheral.delegate = self
        let name = peripheral.name ?? "OBD Adapter"
        state = .connecting(deviceName: name)
        delegate?.obdConnectionStateDidChange(state)

        startConnectionTimeout(deviceName: name)
        centralManager.connect(peripheral, options: nil)
    }

    public func disconnect() {
        centralManager?.stopScan()
        if let peripheral = activePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        state = .disconnected
        resetConnectionState()
        delegate?.obdConnectionStateDidChange(.disconnected)
    }

    private func startConnectionTimeout(deviceName: String) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.connectionTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if case .connecting = self.state {
                self.disconnect()
                self.state = .error("Connection to \(deviceName) timed out")
                self.delegate?.obdConnectionStateDidChange(self.state)
            }
        }
    }

    private func cancelConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
    }

    func resetConnectionState() {
        cancelConnectionTimeout()
        recoveryGeneration += 1
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        isDraining = false
        activePeripheral = nil
        boundService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
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
        guard !isDraining, inFlightCommand == nil, !commandQueue.isEmpty else { return }
        guard commandWriter != nil || (activePeripheral != nil && writeCharacteristic != nil) else {
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

        if let commandWriter {
            commandWriter(data)
        } else if let peripheral = activePeripheral, let writeChar = writeCharacteristic {
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(data, for: writeChar, type: writeType)
        }

        commandTimer?.invalidate()
        commandTimer = Timer.scheduledTimer(withTimeInterval: next.timeout, repeats: false) { [weak self] _ in
            self?.completeInFlight(.failure(NSError(domain: "BluetoothManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Command Timeout"])), rawResponse: nil)
        }
    }

    func completeInFlight(_ result: Result<String, Error>, rawResponse: String?) {
        commandTimer?.invalidate()
        commandTimer = nil
        guard let completed = inFlightCommand else { return }
        inFlightCommand = nil

        let responseText: String
        var wasTimeout = false
        switch result {
        case .success(let raw): responseText = raw
        case .failure(let err):
            responseText = "ERROR: \(err.localizedDescription)"
            wasTimeout = (err as NSError).code == -2
        }
        if wasTimeout {
            // Gate dispatch before observers/completions can enqueue another command.
            isDraining = true
            buffer = ""
            recoveryGeneration += 1
            let generation = recoveryGeneration
            let recovery = DispatchWorkItem { [weak self] in
                guard let self, self.isDraining, self.recoveryGeneration == generation else { return }
                self.recoveryWorkItem = nil
                self.isDraining = false
                self.dispatchNextCommandIfIdle()
            }
            recoveryWorkItem = recovery
            scheduleRecovery(recovery)
        }
        appendLog(sent: completed.command, response: responseText)

        completed.completion?(result)
        if case .success(let raw) = result {
            delegate?.obdConnectionDidReceiveResponse(command: completed.command, rawResponse: raw)
        }

        if !wasTimeout {
            dispatchNextCommandIfIdle()
        }
    }

    func receiveResponseChunk(_ str: String) {
        guard !isDraining, inFlightCommand != nil, !str.isEmpty else { return }
        buffer += str
        if buffer.contains(">") {
            let responseStr = buffer
            buffer = ""
            completeInFlight(.success(responseStr), rawResponse: responseStr)
        }
    }

    private func appendLog(sent: String, response: String) {
        let entry = OBDLogEntry(timestamp: Date(), sent: sent, response: response)
        if let handle = captureHandle {
            do {
                let record = "[\(entry.timestamp.formatted(Self.captureDateFormat))] TX: \(sent)\n\(response)\n\n"
                // ponytail: synchronous per-record I/O; use a bounded writer queue if OBD rates outgrow this.
                try handle.write(contentsOf: Data(record.utf8))
            } catch {
                stopCapture()
                captureError = "Capture stopped: \(error.localizedDescription). Export the capture file to recover partial data; the last record may be incomplete."
            }
        }
        log.append(entry)
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
            resetConnectionState()
            delegate?.obdConnectionStateDidChange(state)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard case .scanning = state else { return }
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }

        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let matchesKnownService = !Set(advertisedServices).isDisjoint(with: Set(BLEConstants.allSupportedServices))

        let targetKeywords = ["vlink", "ios-vlink", "icar", "obd", "ble", "veepeak", "link", "elm", "konnwei", "lelink"]
        let lowerName = name.lowercased()
        let matchesName = targetKeywords.contains { lowerName.contains($0) }

        if matchesKnownService || matchesName {
            central.stopScan()
            activePeripheral = peripheral
            peripheral.delegate = self
            let devName = name.isEmpty ? "OBD Adapter" : name
            state = .connecting(deviceName: devName)
            delegate?.obdConnectionStateDidChange(state)
            startConnectionTimeout(deviceName: devName)
            central.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === activePeripheral, case .connecting = state else { return }
        didRetryServiceDiscovery = false
        peripheral.discoverServices(BLEConstants.allSupportedServices)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === activePeripheral, case .connecting = state else { return }
        let name = peripheral.name ?? "OBD Adapter"
        let msg = error?.localizedDescription ?? "Failed to connect to \(name)"
        resetConnectionState()
        state = .error(msg)
        delegate?.obdConnectionStateDidChange(state)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === activePeripheral else { return }
        state = .disconnected
        resetConnectionState()
        delegate?.obdConnectionStateDidChange(state)
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === activePeripheral, case .connecting = state else { return }
        guard error == nil else {
            let msg = error?.localizedDescription ?? "Service discovery failed"
            resetConnectionState()
            state = .error(msg)
            delegate?.obdConnectionStateDidChange(state)
            return
        }

        let services = peripheral.services ?? []
        let knownServices = services.filter { BLEConstants.allSupportedServices.contains($0.uuid) }

        if !knownServices.isEmpty {
            for service in knownServices {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        } else if !didRetryServiceDiscovery {
            didRetryServiceDiscovery = true
            peripheral.discoverServices(nil)
        } else {
            // Fallback: discover characteristics for any candidate non-standard service
            let candidateServices = services.filter { !BLEConstants.ignoredStandardServices.contains($0.uuid) }
            if candidateServices.isEmpty {
                for service in services {
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            } else {
                for service in candidateServices {
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === activePeripheral, case .connecting = state, error == nil else { return }
        guard boundService == nil else { return }
        guard let characteristics = service.characteristics, !characteristics.isEmpty else { return }

        // 1. Try known write & notify characteristics first
        var write = characteristics.first { BLEConstants.knownWriteCharacteristics.contains($0.uuid) }
        var notify = characteristics.first { BLEConstants.knownNotifyCharacteristics.contains($0.uuid) }

        // 2. Fallback to properties inspection
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
        guard peripheral === activePeripheral, characteristic === notifyCharacteristic else { return }
        guard error == nil, characteristic.isNotifying else {
            if let error = error {
                let msg = "Notification setup failed: \(error.localizedDescription)"
                resetConnectionState()
                state = .error(msg)
                delegate?.obdConnectionStateDidChange(state)
            }
            return
        }
        guard case .connecting = state else { return }
        cancelConnectionTimeout()
        let devName = peripheral.name ?? "OBD Adapter"
        state = .ready(deviceName: devName)
        delegate?.obdConnectionStateDidChange(state)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === activePeripheral, characteristic === notifyCharacteristic, error == nil else { return }
        guard let data = characteristic.value else { return }
        let str = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        receiveResponseChunk(str)
    }
}
