package com.simonkaring.voltlink.core.obd

import java.util.Locale

/**
 * SAE J1979 Mode 02 ("freeze frame") signals: the conditions an ECU recorded when it stored
 * a fault code. Only this small, widely supported set is queried; unsupported PIDs are
 * skipped rather than failing the scan.
 */
enum class FreezeFrameSignal(val pid: Int, val label: String, val unit: String?) {
    ENGINE_LOAD(0x04, "Engine load", "%"),
    COOLANT_TEMP(0x05, "Coolant", "°C"),
    RPM(0x0C, "Engine speed", "rpm"),
    SPEED(0x0D, "Vehicle speed", "km/h"),
    INTAKE_AIR_TEMP(0x0F, "Intake air", "°C"),
    THROTTLE_POSITION(0x11, "Throttle", "%"),
    FUEL_LEVEL(0x2F, "Fuel / charge level", "%"),
    CONTROL_MODULE_VOLTAGE(0x42, "Module voltage", "V"),
    ;

    /** The Mode 02 request for frame 0, e.g. `020D00` for vehicle speed. */
    val command: String get() = String.format(Locale.US, "02%02X00", pid)

    private val byteCount: Int
        get() = if (this == RPM || this == CONTROL_MODULE_VOLTAGE) 2 else 1

    fun decode(bytes: ByteArray): Double? {
        if (bytes.size < byteCount) return null
        val a = (bytes[0].toInt() and 0xFF).toDouble()
        val b = if (byteCount > 1) (bytes[1].toInt() and 0xFF).toDouble() else 0.0
        return when (this) {
            ENGINE_LOAD, THROTTLE_POSITION, FUEL_LEVEL -> a * 100.0 / 255.0
            COOLANT_TEMP, INTAKE_AIR_TEMP -> a - 40.0
            RPM -> (a * 256.0 + b) / 4.0
            SPEED -> a
            CONTROL_MODULE_VOLTAGE -> (a * 256.0 + b) / 1000.0
        }
    }

    fun display(value: Double): String {
        if (!value.isFinite()) return "—"
        val decimals = if (this == CONTROL_MODULE_VOLTAGE) 1 else 0
        val number = String.format(Locale.US, "%.${decimals}f", value)
        return unit?.let { "$number $it" } ?: number
    }

    /** Extracts this signal from a raw ELM327 Mode 02 response; null for negative/no data. */
    fun parse(rawResponse: String): Double? {
        for (frame in IsoTp.assemblePayloads(rawResponse)) {
            val bytes = IsoTp.hexBytes(frame.payload)
            if (bytes.size < 3 + byteCount) continue
            if ((bytes[0].toInt() and 0xFF) != 0x42) continue
            if ((bytes[1].toInt() and 0xFF) != pid) continue
            if ((bytes[2].toInt() and 0xFF) != 0x00) continue
            return decode(bytes.copyOfRange(3, 3 + byteCount))
        }
        return null
    }

    companion object {
        /** Frame values in the stable order the UI renders. */
        fun orderedValues(frames: Map<String, String>): List<Pair<String, String>> =
            entries.mapNotNull { signal -> frames[signal.label]?.let { signal.label to it } }
    }
}
