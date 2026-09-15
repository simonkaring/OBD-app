import Foundation
import Combine

public final class DTCScannerService: ObservableObject {
    @Published public private(set) var scannedCodes: [DTCCode] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanProgress: Double = 0.0
    @Published public private(set) var lastScanDate: Date? = nil
    @Published public private(set) var scanErrorMessage: String? = nil
    @Published public private(set) var scanSucceeded = false

    public var healthSummary: String {
        if isScanning { return "Diagnostics in progress" }
        if let scanErrorMessage { return scanErrorMessage }
        if !scanSucceeded { return "Scan not performed" }
        return scannedCodes.isEmpty ? "No fault codes detected" : "\(scannedCodes.count) fault codes"
    }

    private let db = DTCLocalDatabase.shared
    private let isoParser = ISO15765Parser()
    private var scanManufacturer: String?

    public init() {
        // Surface a bad/missing DTC definitions bundle immediately rather than only on next
        // scan attempt, and without failing the scan itself (generic fallback lookups still work).
        scanErrorMessage = db.loadError
    }

    /// Own the adapter until setup, scanning and profile restoration have all completed.
    public func scanDTCs(vehicleData: VehicleDataManager) {
        guard !isScanning, vehicleData.beginCommandSession() else { return }
        scanDTCs(connection: vehicleData.obdConnection, isDemo: vehicleData.isDemoMode,
                 restoreCommands: vehicleData.isDemoMode ? [] : vehicleData.selectedProfile.initializationCommands,
                 manufacturer: vehicleData.selectedVehicle.brandName) { [weak vehicleData] in
            vehicleData?.endCommandSession(restoreProfile: false)
        }
    }

    public func scanDTCs(connection: OBDConnectionProtocol, isDemo: Bool = false, restoreCommands: [String] = [], manufacturer: String? = nil, completion: @escaping () -> Void = {}) {
        guard !isScanning else { return }
        scanManufacturer = manufacturer
        isScanning = true
        scanProgress = 0.0
        scannedCodes.removeAll()
        scanErrorMessage = nil
        scanSucceeded = false

        if isDemo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                connection.sendCommand("03") { result in
                    self.finishScan(storedResult: result, connection: connection, restoreCommands: [], completion: completion)
                }
            }
            return
        }

        connection.sendSetupCommands(BluetoothManager.diagnosticSetupCommands(for: restoreCommands)) { [weak self] ready in
            guard let self else { return }
            guard ready else {
                self.scanErrorMessage = "Diagnostic adapter setup failed."
                self.restoreProfileAddressing(connection: connection, commands: restoreCommands, completion: completion)
                return
            }
            connection.sendCommand("03") { [weak self] storedResult in
                self?.finishScan(storedResult: storedResult, connection: connection, restoreCommands: restoreCommands, completion: completion)
            }
        }
    }

    private func finishScan(storedResult: Result<String, Error>, connection: OBDConnectionProtocol, restoreCommands: [String], completion: @escaping () -> Void) {
        guard let storedCodes = codes(from: storedResult, serviceByte: 0x43) else {
            scanProgress = 1.0
            lastScanDate = Date()
            scanErrorMessage = "Scan failed — no response from vehicle ECUs."
            restoreProfileAddressing(connection: connection, commands: restoreCommands, completion: completion)
            return
        }

        connection.sendCommand("07") { [weak self] pendingResult in
            guard let self = self else { return }
            self.scanProgress = 1.0
            self.lastScanDate = Date()
            let pendingResultCodes = self.codes(from: pendingResult, serviceByte: 0x47)
            let pendingCodes = pendingResultCodes ?? []
            self.scanSucceeded = pendingResultCodes != nil
            self.scanErrorMessage = pendingResultCodes == nil ? "Partial scan: pending fault codes could not be read." : self.db.loadError
            var combined = storedCodes
            for code in pendingCodes where !combined.contains(where: { $0.code == code.code }) {
                combined.append(code)
            }
            self.scannedCodes = combined
            self.restoreProfileAddressing(connection: connection, commands: restoreCommands, completion: completion)
        }
    }

    private func restoreProfileAddressing(connection: OBDConnectionProtocol, commands: [String], completion: @escaping () -> Void) {
        connection.sendSetupCommands(commands) { [weak self] restored in
            if !restored {
                self?.scanErrorMessage = "Profile restoration failed. Reconnect the scanner."
                self?.scanSucceeded = false
                connection.disconnect()
            }
            self?.isScanning = false
            self?.scanProgress = 1
            completion()
        }
    }

    public func clearDTCs(vehicleData: VehicleDataManager, completion: @escaping (Bool) -> Void) {
        guard !isScanning, vehicleData.beginCommandSession() else { completion(false); return }
        isScanning = true
        scanSucceeded = false
        let connection = vehicleData.obdConnection
        let restore = vehicleData.isDemoMode ? [] : vehicleData.selectedProfile.initializationCommands
        let setup = vehicleData.isDemoMode ? [] : BluetoothManager.diagnosticSetupCommands(for: restore)
        connection.sendSetupCommands(setup) { [weak self, weak vehicleData] ready in
            guard let self else { return }
            let finish: (Bool) -> Void = { success in
                self.scanErrorMessage = success ? nil : "The vehicle did not confirm that codes were cleared."
                self.restoreProfileAddressing(connection: connection, commands: restore) {
                    vehicleData?.endCommandSession(restoreProfile: false)
                    completion(success && self.scanErrorMessage == nil)
                }
            }
            if ready { self.clearDTCs(connection: connection, completion: finish) }
            else { finish(false) }
        }
    }

    public func clearDTCs(connection: OBDConnectionProtocol, completion: @escaping (Bool) -> Void) {
        connection.sendCommand("04") { [weak self] result in
            guard case .success(let raw) = result else {
                completion(false)
                return
            }
            // The raw adapter text still carries the `>` prompt, CAN IDs and ISO-TP PCI
            // bytes; feeding it straight to `hexStringToBytes` yields an odd-length string
            // and therefore an empty byte array, so success was never detected.
            guard let self = self else {
                completion(false)
                return
            }
            let succeeded = self.isoParser.assembleISOTPPayloads(raw).contains { $0.payload.hasPrefix("44") } && !Self.isNegativeOrEmpty(raw)
            if succeeded {
                self.scannedCodes.removeAll()
            }
            completion(succeeded)
        }
    }

    /// Returns decoded codes, or nil if the adapter/ECU reported a failure (as opposed to a clean "0 codes").
    private func codes(from result: Result<String, Error>, serviceByte: UInt8) -> [DTCCode]? {
        guard case .success(let hex) = result, !Self.isNegativeOrEmpty(hex) else { return nil }
        let payloads = isoParser.assembleISOTPPayloads(hex).map { Self.hexStringToBytes($0.payload) }
        let responses = payloads.filter { $0.first == serviceByte }
        guard !responses.isEmpty, responses.allSatisfy({ $0.count >= 2 && $0.count >= 2 + Int($0[1]) * 2 }) else { return nil }
        return parseDTCResponse(hex, serviceByte: serviceByte, manufacturer: scanManufacturer)
    }

    private static func isNegativeOrEmpty(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        return upper.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ["NO DATA", "ERROR", "?", "STOPPED", "UNABLE TO CONNECT", "7F 03", "7F03", "7F 07", "7F07", "7F 04", "7F04"].contains { upper.contains($0) }
    }

    /// `internal` (not `private`) so unit tests can exercise the decoder directly.
    /// Merges DTCs from every responding ECU's ISO-TP bucket (deduped by `.code`, preserving
    /// arrival order) so a broadcast scan where one module reports "no codes" doesn't hide
    /// another module's codes.
    func parseDTCResponse(_ hex: String, serviceByte: UInt8, manufacturer: String? = nil) -> [DTCCode] {
        var results: [DTCCode] = []
        for (_, payload) in isoParser.assembleISOTPPayloads(hex) {
            for code in decodeDTCs(fromPayload: payload, serviceByte: serviceByte, manufacturer: manufacturer)
            where !results.contains(where: { $0.code == code.code }) {
                results.append(code)
            }
        }
        return results
    }

    private func decodeDTCs(fromPayload payload: String, serviceByte: UInt8, manufacturer: String?) -> [DTCCode] {
        let bytes = Self.hexStringToBytes(payload)

        guard let serviceIndex = bytes.firstIndex(of: serviceByte), serviceIndex + 1 < bytes.count else { return [] }

        let count = Int(bytes[serviceIndex + 1])
        var results: [DTCCode] = []
        var index = serviceIndex + 2
        var parsed = 0

        while parsed < count, index + 1 < bytes.count {
            let firstByte = bytes[index]
            let secondByte = bytes[index + 1]
            index += 2
            parsed += 1

            if firstByte == 0 && secondByte == 0 { continue }

            let typePrefix: String
            switch (firstByte & 0xC0) >> 6 {
            case 0: typePrefix = "P"
            case 1: typePrefix = "C"
            case 2: typePrefix = "B"
            case 3: typePrefix = "U"
            default: typePrefix = "P"
            }
            let digit1 = (firstByte & 0x30) >> 4
            let digit2 = firstByte & 0x0F
            let digit3 = (secondByte & 0xF0) >> 4
            let digit4 = secondByte & 0x0F
            let codeStr = String(format: "%@%X%X%X%X", typePrefix, digit1, digit2, digit3, digit4)
            results.append(db.lookup(code: codeStr, manufacturer: manufacturer))
        }
        return results
    }

    private static func hexStringToBytes(_ hex: String) -> [UInt8] {
        let clean = hex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard clean.count % 2 == 0 else { return [] }

        var bytes: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            if let byte = UInt8(clean[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }
}
