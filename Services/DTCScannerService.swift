import Foundation
import Combine

public final class DTCScannerService: ObservableObject {
    @Published public private(set) var scannedCodes: [DTCCode] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanProgress: Double = 0.0
    @Published public private(set) var lastScanDate: Date? = nil

    private let db = DTCLocalDatabase.shared

    public init() {}

    public func scanDTCs(connection: OBDConnectionProtocol, isDemo: Bool = false) {
        isScanning = true
        scanProgress = 0.0
        scannedCodes.removeAll()

        if isDemo {
            // Simulated scan
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                self.scanProgress = 1.0
                self.isScanning = false
                self.lastScanDate = Date()
                if let mock = connection as? MockOBDAdapter, mock.simulationEngine.scenario == .faultInjection {
                    let code = self.db.lookup(code: "P0A80")
                    self.scannedCodes = [code]
                } else {
                    self.scannedCodes = []
                }
            }
            return
        }

        // Real OBD Mode 03 & 07 scan
        connection.sendCommand("03") { [weak self] result in
            guard let self = self else { return }
            self.isScanning = false
            self.scanProgress = 1.0
            self.lastScanDate = Date()
            if case .success(let hex) = result {
                let codes = self.parseDTCResponse(hex)
                self.scannedCodes = codes
            }
        }
    }

    public func clearDTCs(connection: OBDConnectionProtocol, completion: @escaping (Bool) -> Void) {
        connection.sendCommand("04") { [weak self] result in
            if case .success = result {
                self?.scannedCodes.removeAll()
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    private func parseDTCResponse(_ hex: String) -> [DTCCode] {
        let cleanHex = hex.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        guard cleanHex.count >= 4 else { return [] }
        
        var results: [DTCCode] = []
        // Parse Mode 03 responses format: 43 count [B1 B2] [B3 B4]...
        let dataIndex = cleanHex.range(of: "43")?.upperBound ?? cleanHex.startIndex
        let codeData = String(cleanHex[dataIndex...])

        var index = codeData.startIndex
        while codeData.distance(from: index, to: codeData.endIndex) >= 4 {
            let nextIndex = codeData.index(index, offsetBy: 4)
            let pairStr = String(codeData[index..<nextIndex])
            index = nextIndex

            if pairStr == "0000" { continue }

            if let firstByte = UInt8(pairStr.prefix(2), radix: 16),
               let secondByte = UInt8(pairStr.suffix(2), radix: 16) {
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
        }
        return results
    }
}
