package com.simonkaring.voltlink.core.demo

import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.obd.ObdConnection
import com.simonkaring.voltlink.core.obd.ObdLogEntry
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * Demo-mode adapter: answers ELM327 commands from [MockDrivingSimulation] instead of a
 * Bluetooth link, so the whole polling pipeline runs exactly as it does against real
 * hardware. Port of the iOS `MockOBDAdapter`.
 *
 * The simulation starts with [startSimulation], never in the constructor: a demo drive must
 * not run while the app is talking to a real adapter.
 */
class MockObdAdapter(private val scope: CoroutineScope, val simulation: MockDrivingSimulation = MockDrivingSimulation(scope)) : ObdConnection {
    private val _state = MutableStateFlow<BleConnectionState>(BleConnectionState.Disconnected)
    override val state: StateFlow<BleConnectionState> = _state.asStateFlow()

    private val _log = MutableStateFlow<List<ObdLogEntry>>(emptyList())
    override val log: StateFlow<List<ObdLogEntry>> = _log.asStateFlow()

    /** Starts the demo drive and reports the adapter as connected, so polling resumes. */
    fun startSimulation() {
        simulation.start()
        _state.value = BleConnectionState.DemoMode
    }

    fun stopSimulation() {
        simulation.stop()
        _state.value = BleConnectionState.Disconnected
    }

    private fun telemetry(): TelemetrySnapshot = simulation.telemetry.value

    override fun startScan() {
        _state.value = BleConnectionState.DemoMode
    }

    override fun stopScan() = Unit

    override suspend fun connect(deviceAddress: String?) = startSimulation()

    override fun disconnect() = stopSimulation()

    override fun clearLog() {
        _log.value = emptyList()
    }

    override suspend fun sendCommand(command: String): Result<String> {
        delay(50)
        val raw = respondTo(command)
        appendLog(command, raw)
        return Result.success(raw)
    }

    private fun appendLog(command: String, response: String) {
        _log.value = (_log.value + ObdLogEntry(sent = command, response = response)).takeLast(500)
    }

    /** Encodes [command]'s reply from the live simulation state, matching the iOS mock. */
    fun respondTo(command: String): String {
        val telemetry = telemetry()
        fun hex(value: Int): String = String.format(Locale.US, "%02X", value and 0xFF)
        fun word(value: Int): String = hex(value shr 8) + " " + hex(value)

        return when (command) {
            "AT Z", "AT Z\r" -> "ELM327 v2.2\r\n>"
            "AT E0", "AT E0\r", "AT L0", "AT L0\r", "AT S1", "AT H1", "AT CAF 1", "AT SP 0", "AT SP 6", "AT SP 7" ->
                "OK\r\n>"
            "010D", "01 0D" -> "41 0D ${hex(telemetry.speedKmH.toInt())}\r\n>"
            "010C", "01 0C" -> {
                val rawRpm = (telemetry.motorRpm * 4.0).toInt()
                "41 0C ${word(rawRpm)}\r\n>"
            }
            "0142", "01 42" -> "41 42 ${word((telemetry.aux12VVolts * 1000.0).toInt())}\r\n>"
            "22010A", "22 01 0A" -> { // Mercedes EQA pack voltage
                val volts = if (telemetry.voltageV > 0) telemetry.voltageV else 398.0
                "62 01 0A ${word((volts * 10.0).toInt())}\r\n>"
            }
            "22010B", "22 01 0B" -> { // Mercedes EQA pack current
                val rawCurrent = (telemetry.currentA * 10.0).toInt()
                "62 01 0B ${word(rawCurrent)}\r\n>"
            }
            "22010C", "22 01 0C" -> "62 01 0C 08 6A A9\r\n>"
            "0104", "01 04" -> "41 04 ${hex((telemetry.engineLoadPct * 255.0 / 100.0).toInt())}\r\n>"
            "0105", "01 05" -> "41 05 ${hex((telemetry.coolantTempC + 40.0).toInt())}\r\n>"
            "010F", "01 0F" -> "41 0F ${hex((telemetry.intakeAirTempC + 40.0).toInt())}\r\n>"
            "0111", "01 11" -> "41 11 ${hex((telemetry.throttlePositionPct * 255.0 / 100.0).toInt())}\r\n>"
            "012F", "01 2F" -> "41 2F ${hex((telemetry.fuelLevelPct * 255.0 / 100.0).toInt())}\r\n>"
            "015B", "01 5B" -> "41 5B ${hex((telemetry.stateOfChargePct * 255.0 / 100.0).toInt())}\r\n>"
            "0146", "01 46" -> "41 46 ${hex((telemetry.ambientAirTempC + 40.0).toInt())}\r\n>"
            "0110", "01 10" -> "41 10 ${word((telemetry.mafGramsPerSec * 100.0).toInt())}\r\n>"
            "010B", "01 0B" -> "41 0B ${hex(telemetry.manifoldPressureKPa.toInt())}\r\n>"
            "015C", "01 5C" -> "41 5C ${hex((telemetry.oilTempC + 40.0).toInt())}\r\n>"
            "010E", "01 0E" -> "41 0E ${hex(((telemetry.timingAdvanceDeg + 64.0) * 2.0).toInt())}\r\n>"
            "0133", "01 33" -> "41 33 ${hex(telemetry.barometricPressureKPa.toInt())}\r\n>"

            // Freeze frame (Mode 02)
            "020400" -> "42 04 00 ${hex((telemetry.engineLoadPct * 255.0 / 100.0).toInt())}\r\n>"
            "020500" -> "42 05 00 ${hex((telemetry.coolantTempC + 40.0).toInt())}\r\n>"
            "020C00" -> "42 0C 00 ${word((telemetry.motorRpm * 4.0).toInt())}\r\n>"
            "020D00" -> "42 0D 00 ${hex(telemetry.speedKmH.toInt())}\r\n>"
            "020F00" -> "42 0F 00 ${hex((telemetry.intakeAirTempC + 40.0).toInt())}\r\n>"
            "021100" -> "42 11 00 ${hex((telemetry.throttlePositionPct * 255.0 / 100.0).toInt())}\r\n>"
            "022F00" -> "42 2F 00 ${hex((telemetry.fuelLevelPct * 255.0 / 100.0).toInt())}\r\n>"
            "024200" -> "42 42 00 ${word((telemetry.aux12VVolts * 1000.0).toInt())}\r\n>"

            // Mercedes EQA (OBDb community) DIDs
            "222001", "22 20 01" -> {
                val wheelHex = (telemetry.speedKmH / 0.05625).toInt().coerceIn(0, 0xFFFF)
                val raw = StringBuilder("62 20 01")
                repeat(4) { raw.append(' ').append(word(wheelHex)) }
                "$raw\r\n>"
            }
            "222002", "22 20 02" -> "62 20 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00\r\n>"
            "226050", "22 60 50" -> "62 60 50 ${word((telemetry.stateOfChargePct * 100.0).toInt())}\r\n>"
            "226075", "22 60 75" -> "62 60 75 ${word((telemetry.voltageV / 0.025).toInt())}\r\n>"
            "226053", "22 60 53" -> "62 60 53 ${word((-telemetry.currentA * 10.0).toInt())}\r\n>"
            "222005", "22 20 05" -> "62 20 05 ${hex((telemetry.aux12VVolts * 255.0 / 25.9).toInt())}\r\n>"
            "222526", "22 25 26" -> "62 25 26 ${word((telemetry.coolantTempC / 0.125).toInt())}\r\n>"
            "226502", "22 65 02" -> "62 65 02 ${word((telemetry.vehicleRangeKm ?: 300.0).toInt())}\r\n>"
            "226071", "22 60 71" -> "62 60 71 ${word((telemetry.voltageV / 0.025).toInt())}\r\n>"
            "226504", "22 65 04" -> "62 65 04 00 64\r\n>"
            "222525", "22 25 25" -> "62 25 25 ${word((telemetry.batteryTempC * 8).toInt())}\r\n>"
            "220200", "22 02 00" -> "62 02 00 00 00 00 00 00 00 00 00 00\r\n>"
            "220205", "22 02 05" -> "62 02 05 00 00 ${word(telemetry.motorRpm.toInt())} 00 00 00 00 00 00\r\n>"
            "220207", "22 02 07" -> "62 02 07 ${word(((telemetry.motorTorqueNm + 500) * 10).toInt())}\r\n>"
            "220201", "22 02 01" -> "62 02 01 00 00 ${word((telemetry.aux12VVolts * 10).toInt())}\r\n>"

            // Volkswagen MEB DIDs
            "03221E3D55555555" -> {
                val rawVal = maxOf(0, 150_000 - (telemetry.currentA * 100.0).toInt())
                "62 1E 3D ${hex(rawVal shr 24)} ${hex(rawVal shr 16)} ${hex(rawVal shr 8)} ${hex(rawVal)}\r\n>"
            }
            "03221E3B55555555" -> {
                val volts = if (telemetry.voltageV > 0) telemetry.voltageV else 398.0
                "62 1E 3B ${word((volts * 4).toInt())}\r\n>"
            }
            "0322028C55555555" -> {
                val raw = ((telemetry.stateOfChargePct + 7.16) * 2.5 / 1.12).toInt().coerceIn(0, 255)
                "62 02 8C ${hex(raw)}\r\n>"
            }
            "0322744855555555" -> "62 74 48 ${hex(if (telemetry.isCharging) 0x04 else 0x00)}\r\n>"

            // Diagnostics
            "03", "03\r" -> if (simulation.injectedFaultCode.value != null || simulation.scenario == DemoScenario.FAULT_INJECTION) {
                "43 01 0A 80 00 00\r\n>" // P0A80
            } else {
                "43 00 00 00 00 00\r\n>"
            }
            "07" -> "47 00\r\n>"
            "04" -> {
                simulation.clearInjectedFault()
                "44\r\n>"
            }
            "0902" -> "49 02 01 00 00 00 56 4C 54 4B 31 30 30 30 31\r\n>" // VIN: VLTK10001
            else -> "OK\r\n>"
        }
    }
}
