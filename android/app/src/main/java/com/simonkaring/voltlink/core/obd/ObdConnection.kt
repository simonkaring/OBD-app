package com.simonkaring.voltlink.core.obd

import kotlinx.coroutines.flow.StateFlow

/** One line in the OBD terminal log. */
data class ObdLogEntry(
    val timestamp: java.time.Instant = java.time.Instant.now(),
    val sent: String,
    val response: String,
) {
    val id: String get() = "${timestamp.toEpochMilli()}-$sent"
}

/** A BLE (or demo) OBD adapter. Suspending replacement for the iOS callback contract. */
interface ObdConnection {
    val state: StateFlow<BleConnectionState>
    val log: StateFlow<List<ObdLogEntry>>

    /** Scan for nearby adapters; results arrive on [discoveredDevices] until [connect]. */
    fun startScan()
    fun stopScan()
    suspend fun connect(deviceAddress: String? = null)
    fun disconnect()

    /** Writes [command] and suspends until the adapter's reply (or a timeout error). */
    suspend fun sendCommand(command: String): Result<String>

    fun clearLog()
}
