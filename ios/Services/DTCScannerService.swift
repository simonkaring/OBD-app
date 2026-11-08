import Foundation
import Combine

@MainActor
public final class DTCScannerService: ObservableObject {
    @Published public private(set) var scannedCodes: [DTCCode] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanProgress: Double = 0.0
    @Published public private(set) var lastScanDate: Date? = nil
    @Published public private(set) var scanErrorMessage: String? = nil
    @Published public private(set) var scanSucceeded = false
    /// Names the modules whose UDS fault memory did not answer, so a silent module is
    /// never presented as a module without faults.
    @Published public private(set) var moduleScanNotice: String?

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
    @MainActor
    public func scanDTCs(vehicleData: VehicleDataManager) {
        guard !isScanning, vehicleData.beginCommandSession() else { return }
        scanDTCs(
            connection: vehicleData.obdConnection, isDemo: vehicleData.isDemoMode,
            restoreCommands: vehicleData.isDemoMode ? [] : vehicleData.selectedProfile.initializationCommands,
            manufacturer: vehicleData.selectedVehicle.brandName,
            modules: vehicleData.isDemoMode ? [] : vehicleData.selectedProfile.diagnosticModules
        ) { [weak vehicleData] in
            MainActor.assumeIsolated { vehicleData?.endCommandSession(restoreProfile: false) }
        }
    }

    public func scanDTCs(
        connection: OBDConnectionProtocol, isDemo: Bool = false, restoreCommands: [String] = [], manufacturer: String? = nil,
        modules: [DiagnosticModule] = [], completion: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        guard !isScanning else { return }
        scanManufacturer = manufacturer
        isScanning = true
        scanProgress = 0.0
        scannedCodes.removeAll()
        scanErrorMessage = nil
        scanSucceeded = false
        moduleScanNotice = nil

        if isDemo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    connection.sendCommand("03") { result in
                        self.finishScan(
                            storedResult: result, connection: connection, restoreCommands: [], modules: [], completion: completion)
                    }
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
                self?.finishScan(
                    storedResult: storedResult, connection: connection, restoreCommands: restoreCommands,
                    modules: modules, completion: completion)
            }
        }
    }

    private func finishScan(
        storedResult: Result<String, Error>, connection: OBDConnectionProtocol, restoreCommands: [String],
        modules: [DiagnosticModule], completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let storedCodes = codes(from: storedResult, serviceByte: 0x43) else {
            scanProgress = 1.0
            lastScanDate = Date()
            scanErrorMessage = "Scan failed — no response from vehicle ECUs."
            Haptics.error()
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
            self.scanModuleFaultMemories(
                connection: connection, restoreCommands: restoreCommands, modules: modules, completion: completion)
        }
    }

    /// Reads the stored Mode 02 frame for each supported signal and attaches the values to
    /// every code before publishing. A fault is only useful with the conditions it was
    /// recorded under, and an unsupported PID is skipped without failing the scan.
    private func attachFreezeFrames(
        connection: OBDConnectionProtocol,
        restoreCommands: [String],
        remaining: [FreezeFrameSignal] = FreezeFrameSignal.allCases,
        collected: [String: String] = [:],
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let signal = remaining.first else {
            if !collected.isEmpty {
                // A module fault has no Mode 02 frame; only emission codes carry one.
                scannedCodes = scannedCodes.map { code in
                    guard code.moduleName == nil else { return code }
                    var code = code
                    code.freezeFrameData = collected
                    return code
                }
            }
            #if os(iOS)
            NotificationService.shared.notifyFaultCodes(count: scannedCodes.count)
            #endif
            if scannedCodes.isEmpty {
                Haptics.success()
            } else {
                Haptics.warning()
            }
            restoreProfileAddressing(connection: connection, commands: restoreCommands, completion: completion)
            return
        }

        // No codes means no stored frame; skip the extra round trips entirely.
        guard !scannedCodes.isEmpty else {
            attachFreezeFrames(
                connection: connection, restoreCommands: restoreCommands, remaining: [], collected: [:], completion: completion)
            return
        }

        connection.sendCommand(signal.command) { [weak self] result in
            guard let self else { return }
            var frames = collected
            if case .success(let raw) = result, let value = signal.parse(rawResponse: raw) {
                frames[signal.label] = signal.display(value)
            }
            self.attachFreezeFrames(
                connection: connection, restoreCommands: restoreCommands, remaining: Array(remaining.dropFirst()),
                collected: frames, completion: completion)
        }
    }

    /// Reads each module's UDS `19 02` fault memory. Modules are addressed one at a time
    /// because `0x19` is physical-addressed; a module the car does not answer is skipped
    /// and named in `moduleScanNotice` rather than silently counted as fault-free.
    private func scanModuleFaultMemories(
        connection: OBDConnectionProtocol, restoreCommands: [String], modules: [DiagnosticModule],
        index: Int = 0, skipped: [String] = [], completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard index < modules.count else {
            if !skipped.isEmpty {
                moduleScanNotice = "No fault memory from \(skipped.joined(separator: ", "))."
            }
            attachFreezeFrames(connection: connection, restoreCommands: restoreCommands, completion: completion)
            return
        }

        let module = modules[index]
        connection.sendSetupCommands(["AT CRA \(module.responseHeader)", "AT SH \(module.requestHeader)"]) { [weak self] ready in
            guard let self else { return }
            guard ready else {
                self.scanModuleFaultMemories(
                    connection: connection, restoreCommands: restoreCommands, modules: modules,
                    index: index + 1, skipped: skipped + [module.name], completion: completion)
                return
            }
            self.readModuleFaultMemory(
                module, command: UDSDiagnostics.readDTCByStatusMask, allowMaskRetry: true,
                connection: connection, restoreCommands: restoreCommands, modules: modules,
                index: index, skipped: skipped, completion: completion)
        }
    }

    private func readModuleFaultMemory(
        _ module: DiagnosticModule, command: String, allowMaskRetry: Bool,
        connection: OBDConnectionProtocol, restoreCommands: [String], modules: [DiagnosticModule],
        index: Int, skipped: [String], completion: @escaping @MainActor @Sendable () -> Void
    ) {
        connection.sendCommand(command) { [weak self] result in
            guard let self else { return }
            let raw: String
            if case .success(let text) = result { raw = text } else { raw = "" }
            let payloads = self.isoParser.assembleISOTPPayloads(raw)
            let parsed = payloads.map { UDSDiagnostics.codes(fromPayload: $0.payload) }

            if parsed.contains(where: { $0 != nil }) {
                let codes = parsed.compactMap { $0 }.flatMap { $0 }
                    .filter { $0.saeCode != "0000" }
                    .map {
                        self.db.lookupUDS(
                            saeCode: $0.saeCode, failureType: $0.failureType, status: $0.status,
                            module: module.name, manufacturer: self.scanManufacturer)
                    }
                var combined = self.scannedCodes
                for code in codes where !combined.contains(where: { $0.id == code.id }) {
                    combined.append(code)
                }
                self.scannedCodes = combined
                self.scanModuleFaultMemories(
                    connection: connection, restoreCommands: restoreCommands, modules: modules,
                    index: index + 1, skipped: skipped, completion: completion)
                return
            }

            // Some modules reject the full status mask; retry confirmed-only before
            // giving up on the module.
            let nrc = payloads.compactMap { UDSDiagnostics.negativeResponseCode(fromPayload: $0.payload) }.first
            if allowMaskRetry, nrc == 0x31 || nrc == 0x12 {
                self.readModuleFaultMemory(
                    module, command: UDSDiagnostics.readConfirmedDTCs, allowMaskRetry: false,
                    connection: connection, restoreCommands: restoreCommands, modules: modules,
                    index: index, skipped: skipped, completion: completion)
                return
            }

            self.scanModuleFaultMemories(
                connection: connection, restoreCommands: restoreCommands, modules: modules,
                index: index + 1, skipped: skipped + [module.name], completion: completion)
        }
    }

    private func restoreProfileAddressing(connection: OBDConnectionProtocol, commands: [String], completion: @escaping @MainActor @Sendable () -> Void) {
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

    @MainActor
    public func clearDTCs(vehicleData: VehicleDataManager, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard !isScanning, vehicleData.beginCommandSession() else { completion(false); return }
        isScanning = true
        scanSucceeded = false
        let connection = vehicleData.obdConnection
        let restore = vehicleData.isDemoMode ? [] : vehicleData.selectedProfile.initializationCommands
        let setup = vehicleData.isDemoMode ? [] : BluetoothManager.diagnosticSetupCommands(for: restore)
        connection.sendSetupCommands(setup) { [weak self, weak vehicleData] ready in
            guard let self else { return }
            let finish: @MainActor @Sendable (Bool) -> Void = { success in
                self.scanErrorMessage = success ? nil : "The vehicle did not confirm that codes were cleared."
                self.restoreProfileAddressing(connection: connection, commands: restore) {
                    MainActor.assumeIsolated { vehicleData?.endCommandSession(restoreProfile: false) }
                    completion(success && self.scanErrorMessage == nil)
                }
            }
            if ready { self.clearDTCs(connection: connection, completion: finish) } else { finish(false) }
        }
    }

    public func clearDTCs(connection: OBDConnectionProtocol, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        connection.sendCommand("04") { [weak self] result in
            guard case .success(let raw) = result else {
                completion(false)
                return
            }
            // The raw adapter text still carries the `>` prompt, CAN IDs and ISO-TP PCI
            // bytes; feeding it straight to `ISO15765Parser.hexBytes` yields an odd-length string
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
        let payloads = isoParser.assembleISOTPPayloads(hex).map { ISO15765Parser.hexBytes($0.payload) }
        let responses = payloads.filter { $0.first == serviceByte }
        guard !responses.isEmpty, responses.allSatisfy({ $0.count >= 2 && $0.count >= 2 + Int($0[1]) * 2 }) else { return nil }
        return parseDTCResponse(hex, serviceByte: serviceByte, manufacturer: scanManufacturer)
    }

    private static func isNegativeOrEmpty(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        return upper.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || ["NO DATA", "ERROR", "?", "STOPPED", "UNABLE TO CONNECT", "7F 03", "7F03", "7F 07", "7F07", "7F 04", "7F04"].contains { upper.contains($0) }
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
        let bytes = ISO15765Parser.hexBytes(payload)

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

}
