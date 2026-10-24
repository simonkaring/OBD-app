import Foundation

/// Owns the repeating OBD read cycle.
///
/// The previous implementation recursed through `sendCommand` completion handlers and
/// used a generation counter to ignore replies that arrived after polling stopped. A
/// cancellable `Task` replaces that bookkeeping: `stop()` cancels the loop, and a reply
/// that resumes the suspended await is discarded because the task is already cancelled.
@MainActor
final class TelemetryPollingLoop {
    private var task: Task<Void, Never>?
    private var index = 0
    private(set) var isRunning = false

    var commands: @MainActor () -> [String] = { [] }
    var isConnected: @MainActor () -> Bool = { false }
    var send: @MainActor (String) async -> Result<String, Error> = { _ in
        .failure(NSError(domain: "TelemetryPollingLoop", code: -1))
    }
    /// Returns `true` when the read produced applied telemetry.
    var handleRead: @MainActor (_ command: String, _ rawResponse: String) -> Bool = { _, _ in false }
    var handleReadFailure: @MainActor (_ command: String) -> Void = { _ in }
    /// Returns `true` when an `AT` command was acknowledged by the adapter.
    var handleControl: @MainActor (_ command: String, _ result: Result<String, Error>) -> Bool = { _, _ in false }
    var handleControlFailure: @MainActor (_ command: String) -> Void = { _ in }

    var successDelay: Duration = .milliseconds(10)
    var missDelay: Duration = .milliseconds(50)

    func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func resetIndex() {
        index = 0
    }

    private func run() async {
        defer {
            isRunning = false
            task = nil
        }
        while !Task.isCancelled {
            guard isConnected() else {
                if await sleep(.milliseconds(50)) { return }
                continue
            }

            let commands = self.commands()
            guard !commands.isEmpty else {
                if await sleep(.milliseconds(50)) { return }
                continue
            }

            let command = commands[index % commands.count]
            index += 1

            let result = await send(command)
            guard !Task.isCancelled else { return }

            if command.uppercased().hasPrefix("AT") {
                guard handleControl(command, result) else {
                    handleControlFailure(command)
                    return
                }
                if await sleep(successDelay) { return }
                continue
            }

            var delay = successDelay
            switch result {
            case .success(let raw):
                if !handleRead(command, raw) {
                    handleReadFailure(command)
                    delay = missDelay
                }
            case .failure:
                handleReadFailure(command)
                delay = missDelay
            }

            if await sleep(delay) { return }
        }
    }

    /// Returns `true` when the loop should exit (cancellation surfaced at the sleep).
    private func sleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return Task.isCancelled
        } catch {
            return true
        }
    }
}
