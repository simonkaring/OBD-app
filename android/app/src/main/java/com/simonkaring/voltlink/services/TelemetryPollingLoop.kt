package com.simonkaring.voltlink.services

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Owns the repeating OBD read cycle. A cancellable coroutine replaces the iOS loop's
 * generation bookkeeping: stopping cancels the job, and a reply that resumes an in-flight
 * await is discarded because the job is already gone.
 */
class TelemetryPollingLoop(private val scope: CoroutineScope) {
    var commands: () -> List<String> = { emptyList() }
    var isConnected: () -> Boolean = { false }
    var send: suspend (String) -> Result<String> = { Result.failure(IllegalStateException("not connected")) }
    /** Returns true when the read produced applied telemetry. */
    var handleRead: (command: String, rawResponse: String) -> Boolean = { _, _ -> false }
    var handleReadFailure: (command: String) -> Unit = {}
    /** Returns true when an `AT` command was acknowledged by the adapter. */
    var handleControl: (command: String, result: Result<String>) -> Boolean = { _, _ -> false }
    var handleControlFailure: (command: String) -> Unit = {}

    var successDelayMs: Long = 10
    var missDelayMs: Long = 50

    private var job: Job? = null
    private var index = 0

    val isRunning: Boolean get() = job?.isActive == true

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch {
            while (isActive) {
                if (!isConnected()) {
                    delay(50)
                    continue
                }
                val commands = commands()
                if (commands.isEmpty()) {
                    delay(50)
                    continue
                }
                val command = commands[index % commands.size]
                index += 1

                val result = send(command)
                if (!isActive) return@launch

                if (command.uppercase().startsWith("AT")) {
                    if (!handleControl(command, result)) {
                        handleControlFailure(command)
                        return@launch
                    }
                    delay(successDelayMs)
                    continue
                }

                var wait = successDelayMs
                result.onSuccess { raw ->
                    if (!handleRead(command, raw)) {
                        handleReadFailure(command)
                        wait = missDelayMs
                    }
                }.onFailure {
                    handleReadFailure(command)
                    wait = missDelayMs
                }
                delay(wait)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    fun resetIndex() {
        index = 0
    }
}
