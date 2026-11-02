package com.simonkaring.voltlink.data

import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * One car screen row: a telemetry metric, or the always-available health row backed by
 * `DtcScannerService` rather than a telemetry snapshot (the iOS `CarPlayTileKind`).
 */
@Serializable
sealed interface CarTileKind {
    @Serializable
    @SerialName("metric")
    data class Metric(val metric: TelemetryMetric) : CarTileKind

    @Serializable
    @SerialName("health")
    data object Health : CarTileKind

    val title: String
        get() = when (this) {
            is Metric -> metric.displayName
            Health -> "Diagnostics"
        }
}

/** Persisted car pane selection and order, capped at the template's row limit. */
data class CarTileLayout(val tiles: List<CarTileKind>) {
    init {
        require(tiles.size <= MAX_TILES) { "Car layout holds at most $MAX_TILES rows" }
    }

    fun encode(): String = json.encodeToString(tiles)

    companion object {
        /** Android Auto templates stay readable at a glance with at most eight rows. */
        const val MAX_TILES = 8

        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        val default = CarTileLayout(
            tiles = listOf(
                CarTileKind.Metric(TelemetryMetric.SOC),
                CarTileKind.Metric(TelemetryMetric.POWER),
                CarTileKind.Metric(TelemetryMetric.SPEED),
                CarTileKind.Health,
            ),
        )

        fun decode(raw: String?): CarTileLayout {
            if (raw.isNullOrBlank()) return default
            return runCatching {
                val tiles = json.decodeFromString<List<CarTileKind>>(raw)
                CarTileLayout(tiles.take(MAX_TILES))
            }.getOrElse { default }
        }
    }
}
