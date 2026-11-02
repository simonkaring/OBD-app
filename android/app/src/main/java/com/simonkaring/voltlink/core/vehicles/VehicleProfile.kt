package com.simonkaring.voltlink.core.vehicles

import com.simonkaring.voltlink.core.obd.IsoTp
import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.obd.hexByteAfter
import com.simonkaring.voltlink.core.obd.hexBytesAfter
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric

/** A vehicle-specific OBD/UDS definition set. Port of the iOS `VehicleProfile` protocol. */
interface VehicleProfile {
    val vehicleName: String
    val isElectricVehicle: Boolean
    val batteryUsableCapacityKWh: Double
    val initializationCommands: List<String>
    val pollingCommands: List<String>
    val supportedMetrics: Set<TelemetryMetric>

    /** Manufacturer full-charge range (WLTP) used as a conservative estimate basis. */
    val estimatedFullRangeKm: Double?
        get() = null

    /** Whether unverified polling commands are retained for raw capture. */
    val retainUnverifiedPollingCommands: Boolean
        get() = false

    fun parseResponse(command: String, rawResponse: String): TelemetryUpdate?

    /** Like [parseResponse], but a single reply may carry several published signals. */
    fun parseResponses(command: String, rawResponse: String): List<TelemetryUpdate> =
        parseResponse(command, rawResponse)?.let { listOf(it) } ?: emptyList()
}

/** Standard SAE J1979 Mode 01 profile, also the fallback for EVs without a specific profile. */
open class GenericObd2Profile(
    override val vehicleName: String = "Generic SAE J1979 OBD-II",
    override val isElectricVehicle: Boolean = false,
) : VehicleProfile {
    override val batteryUsableCapacityKWh = 0.0

    override val initializationCommands = listOf(
        "AT Z",
        "AT E0",
        "AT L0",
        "AT S1", // Spaces On — required by the space-delimited ISO-TP token parser.
        "AT SP 0", // Auto-detect protocol.
    )

    override val pollingCommands = listOf(
        "010D", // Vehicle speed
        "010C", // Engine RPM
        "0105", // Engine coolant temperature
        "0142", // Control module voltage (12 V)
        "0104", // Calculated engine load
        "010F", // Intake air temperature
        "0111", // Throttle position
        "012F", // Fuel level
        "015B", // Hybrid/EV battery pack remaining life (SAE J1979 EV SoC)
        "0146", // Ambient air temperature
        "0110", // Mass air flow
        "010B", // Intake manifold absolute pressure
        "015C", // Engine oil temperature
        "010E", // Timing advance
        "0133", // Barometric pressure
    )

    override val supportedMetrics = setOf(
        TelemetryMetric.SPEED, TelemetryMetric.MOTOR_RPM, TelemetryMetric.AUX_12V,
        TelemetryMetric.ENGINE_LOAD, TelemetryMetric.COOLANT_TEMP, TelemetryMetric.INTAKE_AIR_TEMP,
        TelemetryMetric.THROTTLE_POSITION, TelemetryMetric.FUEL_LEVEL, TelemetryMetric.SOC,
        TelemetryMetric.AMBIENT_AIR_TEMP, TelemetryMetric.MAF, TelemetryMetric.MANIFOLD_PRESSURE,
        TelemetryMetric.OIL_TEMP, TelemetryMetric.TIMING_ADVANCE, TelemetryMetric.BAROMETRIC_PRESSURE,
    )

    override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? {
        val hex = com.simonkaring.voltlink.core.obd.IsoTp.assemblePayload(rawResponse)
        return when (command.uppercase().replace(" ", "")) {
            "010D" -> hex.hexByteAfter("410D")?.let { TelemetryUpdate.Speed(it.toDouble()) }
            "010C" -> hex.let { h ->
                h.hexBytesAfter("410C", 2)?.let { bytes ->
                    val rpm = ((bytes[0].toInt() and 0xFF) * 256.0 + (bytes[1].toInt() and 0xFF)) / 4.0
                    TelemetryUpdate.MotorStats(rpm, 0.0)
                }
            }
            "0142" -> hex.hexBytesAfter("4142", 2)?.let { bytes ->
                val volts = ((bytes[0].toInt() and 0xFF) * 256.0 + (bytes[1].toInt() and 0xFF)) / 1000.0
                TelemetryUpdate.Aux12V(volts)
            }
            "0105" -> hex.hexByteAfter("4105")?.let { TelemetryUpdate.CoolantTemp(it - 40.0) }
            "0104" -> hex.hexByteAfter("4104")?.let { TelemetryUpdate.EngineLoad(it * 100.0 / 255.0) }
            "010F" -> hex.hexByteAfter("410F")?.let { TelemetryUpdate.IntakeAirTemp(it - 40.0) }
            "0111" -> hex.hexByteAfter("4111")?.let { TelemetryUpdate.ThrottlePosition(it * 100.0 / 255.0) }
            "012F" -> hex.hexByteAfter("412F")?.let { TelemetryUpdate.FuelLevel(it * 100.0 / 255.0) }
            "015B" -> hex.hexByteAfter("415B")?.let { TelemetryUpdate.Soc(it * 100.0 / 255.0) }
            "0146" -> hex.hexByteAfter("4146")?.let { TelemetryUpdate.AmbientAirTemp(it - 40.0) }
            "0110" -> hex.hexBytesAfter("4110", 2)?.let { bytes ->
                TelemetryUpdate.Maf(((bytes[0].toInt() and 0xFF) * 256.0 + (bytes[1].toInt() and 0xFF)) / 100.0)
            }
            "010B" -> hex.hexByteAfter("410B")?.let { TelemetryUpdate.ManifoldPressure(it.toDouble()) }
            "015C" -> hex.hexByteAfter("415C")?.let { TelemetryUpdate.OilTemp(it - 40.0) }
            "010E" -> hex.hexByteAfter("410E")?.let { TelemetryUpdate.TimingAdvance(it / 2.0 - 64.0) }
            "0133" -> hex.hexByteAfter("4133")?.let { TelemetryUpdate.BarometricPressure(it.toDouble()) }
            else -> null
        }
    }
}

/** Generic EV fallback: same SAE J1979 decoding, flagged electric for range/consumption UI. */
class GenericEvProfile : GenericObd2Profile(
    vehicleName = "Generic EV (SAE J1979)",
    isElectricVehicle = true,
)

/** Mercedes-Benz EQA 250 (2021), UDS Service 0x22 on the BMS ECU at 0x59. */
class MercedesEqa250Profile : VehicleProfile {
    override val vehicleName = "Mercedes-Benz EQA 250 (2021)"
    override val isElectricVehicle = true
    override val batteryUsableCapacityKWh = 66.5
    override val estimatedFullRangeKm = 426.0
    override val retainUnverifiedPollingCommands = true

    override val initializationCommands = listOf(
        "AT Z", // Reset ELM327
        "AT E0", // Echo off
        "AT L0", // Linefeed off
        "AT S1", // Spaces on
        "AT H1", // Headers on (CAN ID recognition)
        "AT CAF 1", // CAN auto formatting
        "AT SP 7", // ISO 15765-4 CAN, 29-bit, 500 kbps
        "AT CP 18", // 29-bit CAN priority
        "AT ST FF", // ELM response timeout ~1.02 s
        "ATCRA 18DAF159", // Receive filter for the BMS
        "AT SH 18DA59F1", // Physical addressing: tester (F1) -> BMS (0x59)
        "AT FCSH 18DA59F1",
        "AT FCSD 300000",
        "AT FCSM 1",
    )

    override val pollingCommands = listOf(
        "ATCRA 18DAF159",
        "AT SH 18DA59F1",
        "22010A", // BMS pack voltage, 0.1 V resolution
        "220210", // Raw capture only; DID meaning/scaling unverified
    )

    override val supportedMetrics = setOf(TelemetryMetric.PACK_VOLTAGE)

    override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? {
        val hex = com.simonkaring.voltlink.core.obd.IsoTp.assemblePayload(rawResponse)
        return when (command.uppercase().replace(" ", "")) {
            "22010A" -> hex.hexBytesAfter("62010A", 2)?.let { bytes ->
                TelemetryUpdate.PackVoltage(((bytes[0].toInt() and 0xFF) * 256.0 + (bytes[1].toInt() and 0xFF)) * 0.1)
            }
            // 0x0210 does not reliably match the dashboard state of charge, so it is
            // captured raw and never decoded.
            else -> null
        }
    }
}

/**
 * EQA 250 via the OBDb community signal set (11-bit requests on the 7E2/7E5/624 ECUs).
 * Adaptation of `OBDb/Mercedes-Benz-EQA` (CC BY-SA 4.0); see the iOS profile for provenance.
 */
class MercedesEqaObdbProfile : VehicleProfile {
    override val vehicleName = "Mercedes-Benz EQA 250 (OBDb community)"
    override val isElectricVehicle = true
    override val batteryUsableCapacityKWh = 66.5
    override val estimatedFullRangeKm = 426.0

    override val initializationCommands = listOf(
        "AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT CAF 1",
        "AT SP 6", "AT ST FF", "AT CFC 1", "AT FCSM 0",
        "AT CRA 7ED", "AT SH 7E5",
    )

    override val pollingCommands = listOf(
        // Wheel speed first, so pack-current charging inference has a stationary reading.
        "AT CRA 7EA", "AT SH 7E2", "222001", "222002",
        "AT CRA 7ED", "AT SH 7E5", "226050", "226075", "226053", "222005", "222526", "226502", "226071", "226504",
        "222525", // Drive-unit temperature (EQB community definition)
        "AT CRA 5A4", "AT SH 624", "220201",
        "220200", "220205", "220207", // Machine temperatures, rpm and torque (EQB definitions)
    )

    override val supportedMetrics = setOf(
        TelemetryMetric.SOC, TelemetryMetric.PACK_VOLTAGE, TelemetryMetric.PACK_CURRENT,
        TelemetryMetric.POWER, TelemetryMetric.SPEED, TelemetryMetric.AUX_12V,
        TelemetryMetric.COOLANT_TEMP, TelemetryMetric.VEHICLE_RANGE,
        TelemetryMetric.MOTOR_RPM, TelemetryMetric.MOTOR_TORQUE,
    ) + TelemetryMetric.EQA_COMMUNITY_METRICS

    override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? {
        val cmd = command.uppercase().replace(" ", "")
        if (cmd in MULTI_PAYLOAD_COMMANDS) return parseResponses(cmd, rawResponse).firstOrNull()
        if (cmd !in SINGLE_PAYLOAD_COMMANDS) return null

        val expectedEcu = if (cmd == "222001") "7EA" else "7ED"
        val payload = com.simonkaring.voltlink.core.obd.IsoTp.assemblePayloads(rawResponse)
            .firstOrNull { it.ecu.uppercase() == expectedEcu }?.payload ?: return null
        val marker = "62" + cmd.drop(2)
        if (!payload.startsWith(marker)) return null
        val count = when (cmd) {
            "226502" -> 4
            "222005" -> 1
            else -> 2
        }
        val bytes = payload.hexBytesAfter(marker, count) ?: return null
        fun word(index: Int = 0): Int =
            ((bytes[index].toInt() and 0xFF) shl 8) or (bytes[index + 1].toInt() and 0xFF)

        return when (cmd) {
            "226502" -> {
                val km = bytes.fold(0L) { acc, byte -> (acc shl 8) or (byte.toLong() and 0xFF) }
                if (km <= 1_000) TelemetryUpdate.VehicleRange(km.toDouble()) else null
            }
            "222005" -> TelemetryUpdate.Aux12V((bytes[0].toInt() and 0xFF) * 25.9 / 255.0)
            "222001" -> TelemetryUpdate.Speed(word() * 0.05625) // Front-left wheel
            "226050" -> if (word() <= 10_000) TelemetryUpdate.Soc(word() / 100.0) else null
            "226075" -> TelemetryUpdate.PackVoltage(word() * 0.025)
            "226053" -> TelemetryUpdate.PackCurrent(-word().toShort() / 10.0)
            "222526" -> TelemetryUpdate.CoolantTemp(word().toShort() * 0.125)
            else -> null
        }
    }

    override fun parseResponses(command: String, rawResponse: String): List<TelemetryUpdate> {
        val cmd = command.uppercase().replace(" ", "")
        val ecu = when {
            cmd in setOf("220201", "220200", "220205", "220207") -> "5A4"
            cmd.startsWith("2220") -> "7EA"
            else -> "7ED"
        }
        val payload = com.simonkaring.voltlink.core.obd.IsoTp.assemblePayloads(rawResponse)
            .firstOrNull { it.ecu.uppercase() == ecu }?.payload ?: return emptyList()
        val marker = "62" + cmd.drop(2)
        if (!payload.startsWith(marker)) return emptyList()
        val bytes = payload.hexBytesAfter(marker) ?: return emptyList()

        fun word(index: Int, signed: Boolean = false): Double? {
            if (bytes.size < index + 2) return null
            val bits = ((bytes[index].toInt() and 0xFF) shl 8) or (bytes[index + 1].toInt() and 0xFF)
            return if (signed) bits.toShort().toDouble() else bits.toDouble()
        }
        fun metric(name: TelemetryMetric, value: Double?): List<TelemetryUpdate> =
            value?.let { listOf(TelemetryUpdate.CommunityMetric(name, it)) } ?: emptyList()

        return when (cmd) {
            "222001" -> {
                val result = parseResponse(cmd, rawResponse)?.let { mutableListOf(it) } ?: mutableListOf()
                listOf(
                    TelemetryMetric.FRONT_LEFT_WHEEL_SPEED,
                    TelemetryMetric.FRONT_RIGHT_WHEEL_SPEED,
                    TelemetryMetric.REAR_LEFT_WHEEL_SPEED,
                    TelemetryMetric.REAR_RIGHT_WHEEL_SPEED,
                ).forEachIndexed { index, name ->
                    result += metric(name, word(index * 2)?.let { it * 0.05625 })
                }
                result
            }
            "222002" -> metric(TelemetryMetric.LONGITUDINAL_ACCELERATION, word(1, true)?.let { it * 0.00005 }) +
                metric(TelemetryMetric.LATERAL_ACCELERATION, word(3, true)?.let { it * 0.015625 }) +
                metric(TelemetryMetric.YAW_RATE, word(6, true)?.let { it * 0.003497 }) +
                metric(TelemetryMetric.STEERING_ANGLE, word(9, true)?.let { it * 0.1 }) +
                metric(TelemetryMetric.BRAKE_CYLINDER_PRESSURE, word(12, true)?.let { it * 0.0153 }) +
                metric(TelemetryMetric.VACUUM_BRAKE_PRESSURE, word(18)?.let { it / 1000 })
            "226071" -> metric(TelemetryMetric.CONVERTER_REQUESTED_VOLTAGE, word(0)?.let { it * 0.025 })
            "226504" -> metric(TelemetryMetric.SERVICE_DISTANCE, word(0))
            "220201" -> metric(TelemetryMetric.AUX_12V_HIGH_DEFINITION, word(2)?.let { it * 0.1 })
            "222525" -> metric(TelemetryMetric.DRIVE_UNIT_TEMP, word(0, true)?.let { it / 8 })
            "220200" -> {
                // Rotor, coolant, stator 1 and stator 2 at (raw / 10) - 40 °C; report the
                // hottest sensor, since that is the one limiting drive-unit power.
                if (bytes.size < 10) return emptyList()
                val temps = listOf(word(2, true), word(4, true), word(6, true), word(8, true))
                    .filterNotNull().map { it / 10 - 40 }
                metric(TelemetryMetric.MOTOR_TEMP, temps.maxOrNull())
            }
            "220205" -> {
                // Machine 2 at bytes 2-3, machine 1 at bytes 10-11; a single-motor EQA
                // answers in only one of them.
                val machine1 = if (bytes.size >= 12) word(10) else null
                val machine2 = word(2)
                (machine1?.takeIf { it > 0 } ?: machine2)?.let { listOf(TelemetryUpdate.MotorRpm(it)) } ?: emptyList()
            }
            "220207" -> word(0)?.let { listOf(TelemetryUpdate.MotorTorque(it / 10 - 500)) } ?: emptyList()
            else -> parseResponse(cmd, rawResponse)?.let { listOf(it) } ?: emptyList()
        }
    }

    private companion object {
        val MULTI_PAYLOAD_COMMANDS = setOf("222002", "226071", "226504", "220201", "222525", "220200", "220205", "220207")
        val SINGLE_PAYLOAD_COMMANDS = setOf("222001", "226050", "226075", "226053", "222005", "222526", "226502")
    }
}

/** Volkswagen Group MEB platform (ID.3/ID.4/ID.5/ID.7/ID.Buzz, Enyaq, Born, Q4 e-tron). */
class VolkswagenMebProfile : VehicleProfile {
    override val vehicleName = "Volkswagen MEB (ID.3 / ID.4 / ID.Buzz)"
    override val isElectricVehicle = true
    override val batteryUsableCapacityKWh = 77.0
    override val estimatedFullRangeKm = 400.0

    override val initializationCommands = listOf(
        "AT Z", "AT E0", "AT L0", "AT S1", "AT H1", "AT SP 7", "AT BI",
        "AT SH FC007B", "AT CP 17", "AT CAF 0", "AT CF 17FE7", "AT CRA 17FE007B",
    )

    override val pollingCommands = listOf(
        "03221E3D55555555", // HV current
        "03221E3B55555555", // HV voltage
        "0322028C55555555", // Display SoC
        "0322744855555555", // Charging status
    )

    // No polled DID reports pack temperature, so .batteryTemp is not advertised.
    override val supportedMetrics = setOf(
        TelemetryMetric.POWER, TelemetryMetric.SOC, TelemetryMetric.PACK_VOLTAGE, TelemetryMetric.PACK_CURRENT,
    )

    override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? {
        val hex = com.simonkaring.voltlink.core.obd.IsoTp.assemblePayload(rawResponse)
        return when (command) {
            "03221E3D55555555" -> hex.hexBytesAfter("621E3D", 4)?.let { bytes ->
                var rawVal = 0L
                for (byte in bytes) rawVal = (rawVal shl 8) or (byte.toLong() and 0xFF)
                TelemetryUpdate.PackCurrent(-((rawVal - 150_000.0) / 100.0))
            }
            "03221E3B55555555" -> hex.hexBytesAfter("621E3B", 2)?.let { bytes ->
                TelemetryUpdate.PackVoltage(((bytes[0].toInt() and 0xFF) * 256.0 + (bytes[1].toInt() and 0xFF)) / 4.0)
            }
            "0322028C55555555" -> hex.hexBytesAfter("62028C", 1)?.let { bytes ->
                val soc = (1.12 * (bytes[0].toInt() and 0xFF) / 2.5) - 7.16
                TelemetryUpdate.Soc(soc.coerceIn(0.0, 100.0))
            }
            "0322744855555555" -> hex.hexBytesAfter("627448", 1)?.let { bytes ->
                val status = bytes[0].toInt() and 0xFF
                val isCharging = status and 0x04 != 0
                val isDcfc = status and 0x02 != 0 && isCharging
                // A status bitfield, not a power reading: report an unknown rate while charging.
                TelemetryUpdate.ChargingStats(if (isCharging) null else 0.0, if (isDcfc) "DC" else "AC")
            }
            else -> null
        }
    }
}
