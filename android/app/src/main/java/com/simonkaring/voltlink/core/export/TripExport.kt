package com.simonkaring.voltlink.core.export

import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * File exports for recorded trips and charging sessions.
 *
 * Port of the iOS `TripExport`: the same CSV headers, ISO-8601 timestamps, three-decimal
 * numbers and GPX 1.1 layout, so a file exported from either platform opens the same way in
 * spreadsheets and route tools. Everything here is a pure function of its inputs, which keeps
 * the column order and escaping unit-tested.
 */
object TripExport {

    private val isoFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).withZone(ZoneId.of("UTC"))

    private val filenameStampFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US).withZone(ZoneId.systemDefault())

    // ---------------------------------------------------------------- CSV

    fun csv(trip: TripRecord, samples: List<TripSample> = trip.samples): String {
        val builder = StringBuilder("timestamp,latitude,longitude,speed_kmh,power_kw,soc_pct,battery_temp_c\n")
        samples.sortedBy { it.timestamp }.forEach { sample ->
            val latitude = if (sample.hasValidCoordinate) String.format(Locale.US, "%.6f", sample.latitude) else ""
            val longitude = if (sample.hasValidCoordinate) String.format(Locale.US, "%.6f", sample.longitude) else ""
            builder
                .append(iso(sample.timestamp)).append(',')
                .append(latitude).append(',')
                .append(longitude).append(',')
                .append(number(sample.speedKmH)).append(',')
                .append(number(sample.powerKW)).append(',')
                .append(number(sample.socPct)).append(',')
                .append(number(sample.batteryTempC)).append('\n')
        }
        return builder.toString()
    }

    fun chargingCsv(session: ChargingSessionRecord): String {
        // Column order stays identical to the iOS export; the extra session metadata lives in
        // the app and the backup document, not in this shared CSV contract.
        val header =
            "start_time,end_time,duration_minutes,start_soc_pct,end_soc_pct,energy_kwh,peak_power_kw,average_power_kw,location,latitude,longitude"
        val durationMinutes = session.endTime
            ?.let { java.time.Duration.between(session.startTime, it).toMillis() / 60_000.0 }
            ?.let { String.format(Locale.US, "%.1f", it) }
            ?: ""
        // A session keeps the last known position from when it started; without one the
        // coordinate columns stay empty and the location label carries the context.
        val latitude = if (session.hasLocation) String.format(Locale.US, "%.6f", session.latitude) else ""
        val longitude = if (session.hasLocation) String.format(Locale.US, "%.6f", session.longitude) else ""
        val row = listOf(
            iso(session.startTime),
            session.endTime?.let(::iso) ?: "",
            durationMinutes,
            number(session.startSocPct),
            number(session.endSocPct),
            number(session.totalKWhDelivered),
            number(session.peakPowerKW),
            number(session.averagePowerKW),
            csvField(session.locationName),
            latitude,
            longitude,
        ).joinToString(",")
        return "$header\n$row\n"
    }

    // ---------------------------------------------------------------- GPX

    fun gpx(trip: TripRecord, samples: List<TripSample> = trip.samples): String {
        val name = "${trip.vehicleName} ${trip.startTime.atZone(ZoneId.systemDefault()).format(
            DateTimeFormatter.ofPattern("d MMM yyyy HH:mm", Locale.US),
        )}"
        val route = samples.filter { it.hasValidCoordinate }.sortedBy { it.timestamp }
        val points = route.joinToString("\n") { sample ->
            listOf(
                "      <trkpt lat=\"${String.format(Locale.US, "%.6f", sample.latitude)}\" lon=\"${
                    String.format(Locale.US, "%.6f", sample.longitude)
                }\">",
                "        <time>${iso(sample.timestamp)}</time>",
                "        <extensions>",
                "          <speed>${number(sample.speedKmH)}</speed>",
                "          <power>${number(sample.powerKW)}</power>",
                "          <soc>${number(sample.socPct)}</soc>",
                "        </extensions>",
                "      </trkpt>",
            ).joinToString("\n")
        }
        return buildString {
            appendLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
            appendLine("<gpx version=\"1.1\" creator=\"VoltLink\" xmlns=\"http://www.topografix.com/GPX/1/1\">")
            appendLine("  <metadata>")
            appendLine("    <name>${xmlEscape(name)}</name>")
            appendLine("    <time>${iso(trip.startTime)}</time>")
            appendLine("  </metadata>")
            appendLine("  <trk>")
            appendLine("    <name>${xmlEscape(name)}</name>")
            appendLine("    <trkseg>")
            if (points.isNotEmpty()) appendLine(points)
            appendLine("    </trkseg>")
            appendLine("  </trk>")
            appendLine("</gpx>")
        }
    }

    // ---------------------------------------------------------------- filenames

    fun tripFilename(trip: TripRecord, extension: String): String =
        "VoltLink-Trip-${filenameStampFormatter.format(trip.startTime)}.$extension"

    fun chargingFilename(session: ChargingSessionRecord, extension: String): String =
        "VoltLink-Charging-${filenameStampFormatter.format(session.startTime)}.$extension"

    // ---------------------------------------------------------------- formatting helpers

    /** A trip with no GPS fix still produces a valid (empty) route. */
    fun hasRoute(samples: List<TripSample>): Boolean = samples.any { it.hasValidCoordinate }

    private fun iso(instant: Instant): String = isoFormatter.format(instant)

    private fun number(value: Double): String {
        if (!value.isFinite()) return ""
        return String.format(Locale.US, "%.3f", value)
    }

    private fun csvField(value: String): String {
        if (value.none { it == ',' || it == '"' || it == '\n' }) return value
        return "\"" + value.replace("\"", "\"\"") + "\""
    }

    private fun xmlEscape(value: String): String = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")
}
