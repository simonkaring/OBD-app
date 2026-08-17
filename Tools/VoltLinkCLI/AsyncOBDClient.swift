import Foundation
import CoreBluetooth
import VoltLinkEngine

public final class AsyncOBDClient: NSObject, OBDConnectionDelegate {
    private let manager: BluetoothManager
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var isConnected = false
    
    public override init() {
        self.manager = BluetoothManager()
        super.init()
        self.manager.delegate = self
    }
    
    public func connect(timeout: TimeInterval = 10.0) async throws {
        if manager.state.isConnected { return }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionContinuation = continuation
            
            // Trigger scan/connection
            self.manager.connect(peripheralName: nil)
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = self.connectionContinuation {
                    self.connectionContinuation = nil
                    cont.resume(throwing: NSError(domain: "VoltLinkCLI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timed out after \(Int(timeout))s"]))
                }
            }
        }
    }
    
    public func disconnect() {
        manager.disconnect()
    }
    
    public func sendRaw(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            manager.sendCommand(command) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func initializeELM327(protocolNumber: String = "7") async throws {
        let initSequence = [
            "AT Z",
            "AT E0",
            "AT L0",
            "AT S1",
            "AT H1",
            "AT CAF 1",
            "AT ST FF",
            "AT AL",
            "AT SP \(protocolNumber)"
        ]
        
        for cmd in initSequence {
            _ = try await sendRaw(cmd)
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms pause between init commands
        }
    }
    
    // MARK: - OBDConnectionDelegate
    
    public func obdConnectionDidReceiveResponse(command: String, rawResponse: String) {}
    
    public func obdConnectionStateDidChange(_ state: BLEConnectionState) {
        if state.isConnected {
            if let cont = connectionContinuation {
                connectionContinuation = nil
                cont.resume()
            }
        } else if case .error(let message) = state {
            if let cont = connectionContinuation {
                connectionContinuation = nil
                cont.resume(throwing: NSError(domain: "VoltLinkCLI", code: -2, userInfo: [NSLocalizedDescriptionKey: message]))
            }
        }
    }
}
