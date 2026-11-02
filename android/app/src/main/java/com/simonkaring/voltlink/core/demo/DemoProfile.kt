package com.simonkaring.voltlink.core.demo

import com.simonkaring.voltlink.core.obd.IsoTp
import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.obd.hexBytesAfter
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.vehicles.GenericObd2Profile
import com.simonkaring.voltlink.core.vehicles.VehicleProfile

/**
 * Demo-mode profile: the simulated adapter answers both the generic SAE J1979 PIDs and the
 * EQA BMS DIDs, so demo mode can populate power, SoC and every generic metric regardless of
 * which vehicle profile the user has selected. Never used against real hardware.
 */
class DemoProfile : VehicleProfile {
    override val vehicleName = "VoltLink Demo Vehicle"
    override val isElectricVehicle = true
    override val batteryUsableCapacityKWh = 66.5
    override val estimatedFullRangeKm = 426.0

    private val generic = GenericObd2Profile()

    override val initializationCommands = generic.initializationCommands

    override val pollingCommands = generic.pollingCommands + listOf(
        "22010A", // BMS pack voltage
        "22010B", // BMS pack current
    )

    override val supportedMetrics: Set<TelemetryMetric> =
        generic.supportedMetrics + setOf(
            TelemetryMetric.POWER,
            TelemetryMetric.PACK_VOLTAGE,
            TelemetryMetric.PACK_CURRENT,
            TelemetryMetric.BATTERY_TEMP,
        )

    override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? {
        generic.parseResponse(command, rawResponse)?.let { return it }
        val hex = IsoTp.assemblePayload(rawResponse)
        return when (command.uppercase().replace(" ", "")) {
            "22010A" -> hex.hexBytesAfter("62010A", 2)?.let { bytes ->
                TelemetryUpdate.PackVoltage(((bytes[0].toInt() and 0xFF) * 256.0 + (bytes[1].toInt() and 0xFF)) * 0.1)
            }
            "22010B" -> hex.hexBytesAfter("62010B", 2)?.let { bytes ->
                val raw = ((bytes[0].toInt() and 0xFF) shl 8) or (bytes[1].toInt() and 0xFF)
                TelemetryUpdate.PackCurrent(raw.toShort() / 10.0)
            }
            else -> null
        }
    }
}
