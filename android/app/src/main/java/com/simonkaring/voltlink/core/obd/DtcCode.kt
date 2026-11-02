package com.simonkaring.voltlink.core.obd

enum class DtcSeverity(val label: String) {
    CRITICAL("Critical"),
    WARNING("Warning"),
    ADVISORY("Advisory"),
    UNKNOWN("Unknown"),
    ;

    companion object {
        fun from(label: String?): DtcSeverity = entries.firstOrNull { it.label.equals(label, ignoreCase = true) } ?: UNKNOWN
    }
}

data class DtcCode(
    val code: String,
    val title: String,
    val category: String,
    val severity: DtcSeverity,
    val description: String,
    val symptoms: List<String> = emptyList(),
    val possibleFixes: List<String> = emptyList(),
    val freezeFrameData: Map<String, String>? = null,
    val timestamp: java.time.Instant = java.time.Instant.now(),
    val definitionSource: String? = null,
)
