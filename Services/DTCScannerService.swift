import Foundation
import Combine

public final class DTCScannerService: ObservableObject {
    @Published public private(set) var scannedCodes: [DTCCode] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanProgress: Double = 0.0
    @Published public private(set) var lastScanDate: Date? = nil
    @Published public private(set) var scanErrorMessage: String? = nil

    private let db = DTCLocalDatabase.shared
    private let isoParser = ISO15765Parser()

    public init() {}

    /// - Parameter restoreCommands: the active vehicle profile's initialization commands.
    ///   Mode 03/07 need broadcast addressing, which means clobbering whatever header and
    ///   receive filter the profile set up; these are replayed afterwards so polling keeps
    ///   talking to the right ECU (profiles like VW MEB never re-send `AT SH` while polling).
    public func scanDTCs(connection: OBDConnectionProtocol, isDemo: Bool = false, restoreCommands: [String] = []) {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        scannedCodes.removeAll()
        scanErrorMessage = nil

        if isDemo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                connection.sendCommand("03") { result in
                    self.finishScan(storedResult: result, connection: connection, restoreCommands: [])
                }
            }
            return
        }

        // Broadcast header so Mode 03/07 reach every ECU, not just whichever module a
        // vehicle profile last selected (e.g. Mercedes profile leaves the header on 7E4/BMS).
        // `AT CRA` with no argument resets the receive filter — without it a profile-set
        // filter (e.g. Mercedes' `ATCRA 18DAF159`) drops every broadcast reply.
        connection.sendCommand("AT CRA", completion: nil)
        connection.sendCommand("AT SH 7DF", completion: nil)
        connection.sendCommand("03") { [weak self] storedResult in
            self?.finishScan(storedResult: storedResult, connection: connection, restoreCommands: restoreCommands)
        }
    }

    private func finishScan(storedResult: Result<String, Error>, connection: OBDConnectionProtocol, restoreCommands: [String]) {
        guard let storedCodes = codes(from: storedResult, serviceByte: 0x43) else {
            isScanning = false
            scanProgress = 1.0
            lastScanDate = Date()
            scanErrorMessage = "Scan failed — no response from vehicle ECUs."
            restoreProfileAddressing(connection: connection, commands: restoreCommands)
            return
        }

        connection.sendCommand("07") { [weak self] pendingResult in
            guard let self = self else { return }
            self.isScanning = false
            self.scanProgress = 1.0
            self.lastScanDate = Date()
            let pendingCodes = self.codes(from: pendingResult, serviceByte: 0x47) ?? []
            var combined = storedCodes
            for code in pendingCodes where !combined.contains(where: { $0.code == code.code }) {
                combined.append(code)
            }
            self.scannedCodes = combined
            self.restoreProfileAddressing(connection: connection, commands: restoreCommands)
        }
    }

    private func restoreProfileAddressing(connection: OBDConnectionProtocol, commands: [String]) {
        for command in commands {
            connection.sendCommand(command, completion: nil)
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
            let payload = self.isoParser.assembleISOTPPayload(raw)
            let bytes = Self.hexStringToBytes(payload)
            let succeeded = bytes.contains(0x44) && !Self.isNegativeOrEmpty(raw)
            if succeeded {
                self.scannedCodes.removeAll()
            }
            completion(succeeded)
        }
    }

    /// Returns decoded codes, or nil if the adapter/ECU reported a failure (as opposed to a clean "0 codes").
    private func codes(from result: Result<String, Error>, serviceByte: UInt8) -> [DTCCode]? {
        guard case .success(let hex) = result, !Self.isNegativeOrEmpty(hex) else { return nil }
        return parseDTCResponse(hex, serviceByte: serviceByte)
    }

    private static func isNegativeOrEmpty(_ raw: String) -> Bool {
        let upper = raw.uppercased()
        return upper.contains("NO DATA") || upper.contains("BUS ERROR") || upper.contains("UNABLE TO CONNECT") || upper.contains("7F 03") || upper.contains("7F03") || upper.contains("7F 07") || upper.contains("7F07") || upper.contains("7F 04") || upper.contains("7F04")
    }

    /// `internal` (not `private`) so unit tests can exercise the decoder directly.
    func parseDTCResponse(_ hex: String, serviceByte: UInt8) -> [DTCCode] {
        let payload = isoParser.assembleISOTPPayload(hex)
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
            results.append(db.lookup(code: codeStr))
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
