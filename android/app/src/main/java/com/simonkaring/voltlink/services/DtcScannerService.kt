package com.simonkaring.voltlink.services

import com.simonkaring.voltlink.core.obd.DtcCode
import com.simonkaring.voltlink.core.obd.FreezeFrameSignal
import com.simonkaring.voltlink.core.obd.IsoTp
import com.simonkaring.voltlink.data.DtcLocalDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.Locale

data class DiagnosticsState(
    val codes: List<DtcCode> = emptyList(),
    val isScanning: Boolean = false,
    val progress: Double = 0.0,
    val lastScanDate: Instant? = null,
    val errorMessage: String? = null,
    val scanSucceeded: Boolean = false,
) {
    val healthSummary: String
        get() = when {
            isScanning -> "Diagnostics in progress"
            errorMessage != null -> errorMessage
            !scanSucceeded -> "Scan not performed"
            codes.isEmpty() -> "No fault codes detected"
            codes.size == 1 -> "1 fault code"
            else -> "${codes.size} fault codes"
        }
}

/**
 * Mode 03/07 fault-code scan with Mode 02 freeze frames and Mode 04 clearing. Port of the
 * iOS `DTCScannerService`, including the adapter setup/restore around the scan.
 */
class DtcScannerService(
    private val scope: CoroutineScope,
    private val manager: VehicleDataManager,
    private val database: DtcLocalDatabase,
) {
    private val _state = MutableStateFlow(DiagnosticsState(errorMessage = database.loadError))
    val state: StateFlow<DiagnosticsState> = _state.asStateFlow()

    private var manufacturer: String? = null

    fun scan() {
        if (_state.value.isScanning) return
        if (!manager.beginCommandSession()) return
        manufacturer = selectedManufacturer()
        _state.value = DiagnosticsState(isScanning = true)

        scope.launch {
            try {
                database.awaitLoaded()
                if (manager.isDemoMode.value) {
                    delay(1_500)
                    finishScan(manager.sendCommandResult("03"))
                    return@launch
                }
                val setup = diagnosticSetupCommands(manager.selectedProfile.initializationCommands)
                val ready = manager.sendSetupCommands(setup)
                if (!ready) {
                    _state.value = _state.value.copy(
                        isScanning = false,
                        progress = 1.0,
                        errorMessage = "Diagnostic adapter setup failed.",
                    )
                    return@launch
                }
                finishScan(manager.sendCommandResult("03"))
            } finally {
                restoreProfileAddressing()
                manager.endCommandSession(restoreProfile = false)
            }
        }
    }

    private suspend fun finishScan(storedResult: Result<String>) {
        val storedCodes = codes(storedResult, serviceByte = 0x43)
        if (storedCodes == null) {
            _state.value = _state.value.copy(
                isScanning = false,
                progress = 1.0,
                lastScanDate = Instant.now(),
                errorMessage = "Scan failed — no response from vehicle ECUs.",
            )
            return
        }

        val pendingResult = manager.sendCommandResult("07")
        val pendingCodes = codes(pendingResult, serviceByte = 0x47)
        val combined = storedCodes.toMutableList()
        pendingCodes.orEmpty().forEach { code ->
            if (combined.none { it.code == code.code }) combined += code
        }
        _state.value = _state.value.copy(
            progress = 1.0,
            lastScanDate = Instant.now(),
            scanSucceeded = pendingCodes != null,
            errorMessage = if (pendingCodes == null) {
                "Partial scan: pending fault codes could not be read."
            } else {
                database.loadError
            },
            codes = combined,
        )

        attachFreezeFrames()
        _state.value = _state.value.copy(isScanning = false, progress = 1.0)
    }

    /** Reads the stored Mode 02 frame; unsupported PIDs are skipped. */
    private suspend fun attachFreezeFrames() {
        if (_state.value.codes.isEmpty()) return
        val frames = mutableMapOf<String, String>()
        for (signal in FreezeFrameSignal.entries) {
            val raw = manager.sendCommandResult(signal.command).getOrNull() ?: continue
            val value = signal.parse(raw) ?: continue
            frames[signal.label] = signal.display(value)
        }
        if (frames.isNotEmpty()) {
            _state.value = _state.value.copy(codes = _state.value.codes.map { it.copy(freezeFrameData = frames) })
        }
    }

    fun clearCodes() {
        if (_state.value.isScanning) return
        if (!manager.beginCommandSession()) return
        _state.value = _state.value.copy(isScanning = true, scanSucceeded = false)
        scope.launch {
            try {
                if (!manager.isDemoMode.value) {
                    val setup = diagnosticSetupCommands(manager.selectedProfile.initializationCommands)
                    if (!manager.sendSetupCommands(setup)) {
                        _state.value = _state.value.copy(
                            isScanning = false,
                            errorMessage = "The vehicle did not confirm that codes were cleared.",
                        )
                        return@launch
                    }
                }
                val raw = manager.sendCommandResult("04").getOrNull()
                val succeeded = raw != null && !isNegativeOrEmpty(raw) &&
                    IsoTp.assemblePayloads(raw).any { it.payload.startsWith("44") }
                if (succeeded) {
                    _state.value = _state.value.copy(codes = emptyList(), errorMessage = null)
                } else {
                    _state.value = _state.value.copy(
                        errorMessage = "The vehicle did not confirm that codes were cleared.",
                    )
                }
            } finally {
                _state.value = _state.value.copy(isScanning = false)
                restoreProfileAddressing()
                manager.endCommandSession(restoreProfile = false)
            }
        }
    }

    private suspend fun restoreProfileAddressing() {
        if (manager.isDemoMode.value) return
        val restored = manager.sendSetupCommands(manager.selectedProfile.initializationCommands)
        if (!restored) {
            _state.value = _state.value.copy(
                errorMessage = "Profile restoration failed. Reconnect the scanner.",
                scanSucceeded = false,
            )
            manager.disconnect()
        }
    }

    /** Returns decoded codes, or null when the adapter/ECU reported a failure. */
    private fun codes(result: Result<String>, serviceByte: Int): List<DtcCode>? {
        val hex = result.getOrNull() ?: return null
        if (isNegativeOrEmpty(hex)) return null
        val payloads = IsoTp.assemblePayloads(hex).map { IsoTp.hexBytes(it.payload) }
        val responses = payloads.filter { it.isNotEmpty() && (it[0].toInt() and 0xFF) == serviceByte }
        val valid = responses.isNotEmpty() && responses.all { bytes ->
            val count = (bytes[1].toInt() and 0xFF)
            bytes.size >= 2 + count * 2
        }
        if (!valid) return null
        return parseDtcResponse(hex, serviceByte, manufacturer)
    }

    /** Merges codes from every responding ECU bucket, deduped by code, preserving arrival order. */
    fun parseDtcResponse(hex: String, serviceByte: Int, manufacturer: String? = null): List<DtcCode> {
        val results = mutableListOf<DtcCode>()
        for (frame in IsoTp.assemblePayloads(hex)) {
            for (code in decodeDtcCodes(frame.payload, serviceByte, manufacturer)) {
                if (results.none { it.code == code.code }) results += code
            }
        }
        return results
    }

    private fun decodeDtcCodes(payload: String, serviceByte: Int, manufacturer: String?): List<DtcCode> {
        val bytes = IsoTp.hexBytes(payload)
        val serviceIndex = bytes.indexOfFirst { (it.toInt() and 0xFF) == serviceByte }
        if (serviceIndex < 0 || serviceIndex + 1 >= bytes.size) return emptyList()

        val count = bytes[serviceIndex + 1].toInt() and 0xFF
        val results = mutableListOf<DtcCode>()
        var index = serviceIndex + 2
        var parsed = 0
        while (parsed < count && index + 1 < bytes.size) {
            val first = bytes[index].toInt() and 0xFF
            val second = bytes[index + 1].toInt() and 0xFF
            index += 2
            parsed += 1
            if (first == 0 && second == 0) continue

            val prefix = when ((first and 0xC0) shr 6) {
                0 -> "P"
                1 -> "C"
                2 -> "B"
                else -> "U"
            }
            val code = String.format(
                Locale.US,
                "%s%X%X%X%X",
                prefix,
                (first and 0x30) shr 4,
                first and 0x0F,
                (second and 0xF0) shr 4,
                second and 0x0F,
            )
            results += database.lookup(code, manufacturer)
        }
        return results
    }

    private fun selectedManufacturer(): String? = when (manager.selectedProfileId.value) {
        com.simonkaring.voltlink.core.vehicles.VehicleProfileId.MERCEDES_EQ_A250,
        com.simonkaring.voltlink.core.vehicles.VehicleProfileId.MERCEDES_EQ_A_OBDb,
        -> "Mercedes-Benz"
        com.simonkaring.voltlink.core.vehicles.VehicleProfileId.VOLKSWAGEN_MEB -> "Volkswagen"
        else -> "Generic"
    }

    private fun isNegativeOrEmpty(raw: String): Boolean {
        val upper = raw.uppercase().trim()
        if (upper.isEmpty()) return true
        return listOf(
            "NO DATA", "ERROR", "?", "STOPPED", "UNABLE TO CONNECT",
            "7F 03", "7F03", "7F 07", "7F07", "7F 04", "7F04",
        ).any { upper.contains(it) }
    }

    companion object {
        /** Reset to functional addressing, keeping the profile's chosen bus protocol. */
        fun diagnosticSetupCommands(profileCommands: List<String>): List<String> {
            val commands = mutableListOf("AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT CAF 1", "AT SP 0")
            val selectProtocol = profileCommands.lastOrNull {
                it.replace(" ", "").uppercase().startsWith("ATSP")
            }
            if (selectProtocol != null) commands[commands.lastIndex] = selectProtocol
            return commands
        }
    }
}
