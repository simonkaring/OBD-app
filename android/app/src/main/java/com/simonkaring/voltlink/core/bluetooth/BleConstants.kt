package com.simonkaring.voltlink.core.bluetooth

import java.util.UUID

/**
 * GATT profiles used by BLE OBD-II adapters (Vgate iCar Pro 2S, HM-10, Nordic UART,
 * generic ELM327 clones). Port of the iOS `BLEConstants`.
 */
object BleConstants {
    // Vgate iCar Pro 2S / iOS-Vlink standard BLE GATT profile (18F0)
    val VGATE_SERVICE: UUID = uuid("000018F0-0000-1000-8000-00805F9B34FB")
    val VGATE_WRITE_CHAR: UUID = uuid("00002AF1-0000-1000-8000-00805F9B34FB")
    val VGATE_NOTIFY_CHAR: UUID = uuid("00002AF0-0000-1000-8000-00805F9B34FB")

    // Vgate vLinker / ios-vlink 128-bit custom profile
    val VGATE128_SERVICE: UUID = uuid("E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    val VGATE128_CHAR: UUID = uuid("BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")

    // HM-10 / CC2541 / generic ELM327 BLE (FFE0)
    val HM10_SERVICE: UUID = uuid("0000FFE0-0000-1000-8000-00805F9B34FB")
    val HM10_CHAR: UUID = uuid("0000FFE1-0000-1000-8000-00805F9B34FB")

    // Veepeak / generic ELM327 custom UART (FFF0)
    val GENERIC_UART_SERVICE: UUID = uuid("0000FFF0-0000-1000-8000-00805F9B34FB")
    val GENERIC_UART_WRITE: UUID = uuid("0000FFF2-0000-1000-8000-00805F9B34FB")
    val GENERIC_UART_NOTIFY: UUID = uuid("0000FFF1-0000-1000-8000-00805F9B34FB")

    // Nordic UART Service
    val NORDIC_UART_SERVICE: UUID = uuid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    val NORDIC_UART_WRITE: UUID = uuid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    val NORDIC_UART_NOTIFY: UUID = uuid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // Microchip / ISSC BLE profile
    val ISSC_SERVICE: UUID = uuid("49535343-FE7D-4AE5-8FA9-9FAFF207E245")
    val ISSC_WRITE_CHAR: UUID = uuid("49535343-8841-43F4-A8D4-ECBE34729BB3")
    val ISSC_NOTIFY_CHAR: UUID = uuid("49535343-1E4D-4BD9-BA61-23C647249616")

    val SUPPORTED_SERVICES: List<UUID> = listOf(
        VGATE_SERVICE,
        VGATE128_SERVICE,
        HM10_SERVICE,
        GENERIC_UART_SERVICE,
        NORDIC_UART_SERVICE,
        ISSC_SERVICE,
    )

    val KNOWN_WRITE_CHARACTERISTICS: Set<UUID> = setOf(
        VGATE_WRITE_CHAR, VGATE128_CHAR, HM10_CHAR, GENERIC_UART_WRITE, NORDIC_UART_WRITE, ISSC_WRITE_CHAR,
    )

    val KNOWN_NOTIFY_CHARACTERISTICS: Set<UUID> = setOf(
        VGATE_NOTIFY_CHAR, VGATE128_CHAR, HM10_CHAR, GENERIC_UART_NOTIFY, NORDIC_UART_NOTIFY, ISSC_NOTIFY_CHAR,
    )

    /** Standard BLE SIG informational services that must not be used as a UART channel. */
    val IGNORED_STANDARD_SERVICES: Set<UUID> = setOf(
        uuid("00001800-0000-1000-8000-00805F9B34FB"), // Generic Access
        uuid("00001801-0000-1000-8000-00805F9B34FB"), // Generic Attribute
        uuid("0000180A-0000-1000-8000-00805F9B34FB"), // Device Information
        uuid("0000180F-0000-1000-8000-00805F9B34FB"), // Battery Service
    )

    const val CLIENT_CHARACTERISTIC_CONFIG: String = "00002902-0000-1000-8000-00805F9B34FB"

    const val DEFAULT_TIMEOUT_MS: Long = 4_000
    const val CONNECTION_TIMEOUT_MS: Long = 10_000

    /**
     * Grace period after a command timeout before dispatching the next command, so a late
     * notification for the timed-out command drains instead of polluting the next response.
     */
    const val STALE_RESPONSE_DRAIN_DELAY_MS: Long = 300

    /** Names that identify an OBD-II adapter during a scan. */
    const val ADAPTER_NAME_HINT_REGEX = "(?i)(vgate|vlinker|obd|elm|icar|veepeak|konnwei|carista|kds)"

    private fun uuid(value: String): UUID = UUID.fromString(value)
}
