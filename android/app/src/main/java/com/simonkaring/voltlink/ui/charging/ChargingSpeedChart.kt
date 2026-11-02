package com.simonkaring.voltlink.ui.charging

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.data.ChargingSample
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.theme.Theme
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/** One charge-power reading placed on a session timeline, like the iOS `ChargingSpeedPoint`. */
data class ChargingSpeedPoint(
    /** Minutes elapsed since the first reading of the session. */
    val minute: Double,
    val powerKW: Double,
    /** Battery level at the reading, when the source reported one. */
    val socPct: Double? = null,
)

/** Builds charge-speed curves from persisted session samples. */
object ChargingSpeedCurve {
    fun session(samples: List<ChargingSample>, limit: Int = 240): List<ChargingSpeedPoint> {
        val readings = samples
            .filter { it.powerKW.isFinite() && it.timestamp.toEpochMilli().toDouble().isFinite() }
            .sortedBy { it.timestamp }
            .map { Triple(it.timestamp.toEpochMilli(), it.powerKW, it.socPct) }
        return curve(readings, limit)
    }

    fun curve(readings: List<Triple<Long, Double, Double>>, limit: Int = 240): List<ChargingSpeedPoint> {
        if (readings.size <= 1) return emptyList()
        val origin = readings.first().first
        val points = readings.map { (epochMillis, powerKW, socPct) ->
            ChargingSpeedPoint(
                minute = TimeUnit.MILLISECONDS.toSeconds(epochMillis - origin).coerceAtLeast(0) / 60.0,
                powerKW = powerKW.coerceAtLeast(0.0),
                socPct = socPct.takeIf { it.isFinite() && it > 0 },
            )
        }
        return points.downsampled(limit)
    }

}

/** Evenly spaced subset so a long session stays cheap to render. */
fun List<ChargingSpeedPoint>.downsampled(limit: Int): List<ChargingSpeedPoint> {
    if (limit <= 1 || size <= limit) return this
    val step = (size - 1).toDouble() / (limit - 1)
    return (0 until limit).map { this[(it * step).toInt()] }
}

/**
 * Charge power over time with a scrubbable readout of elapsed time, speed and state of charge —
 * the Android equivalent of the iOS `ChargingSpeedChart`.
 */
@Composable
fun ChargingSpeedChart(
    points: List<ChargingSpeedPoint>,
    units: UnitPrefs,
    modifier: Modifier = Modifier,
) {
    if (points.size < 2) return
    var selectedMinute by remember(points) { mutableStateOf<Double?>(null) }
    val lastMinute = points.last().minute
    val peak = maxOf(points.maxOf { it.powerKW }, 1.0)
    val selected = selectedMinute?.let { minute -> points.minByOrNull { abs(it.minute - minute) } }

    fun select(x: Float, width: Float) {
        if (width <= 0f) return
        selectedMinute = ((x / width).coerceIn(0f, 1f).toDouble() * lastMinute)
    }

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(170.dp)
                .pointerInput(points) {
                    detectDragGestures(
                        onDragStart = { offset -> select(offset.x, size.width.toFloat()) },
                        onDrag = { change, _ ->
                            change.consume()
                            select(change.position.x, size.width.toFloat())
                        },
                    )
                }
                .pointerInput(points) {
                    detectTapGestures { offset -> select(offset.x, size.width.toFloat()) }
                },
        ) {
            val plotHeight = size.height - 6.dp.toPx()
            val maxValue = peak * 1.1
            fun xFor(minute: Double): Float =
                if (lastMinute <= 0.0) 0f else (minute / lastMinute * size.width).toFloat()
            fun yFor(powerKW: Double): Float = (plotHeight - (powerKW / maxValue) * plotHeight).toFloat()

            // Baseline and mid grid lines.
            repeat(3) { index ->
                val y = plotHeight * index / 2f
                drawLine(
                    color = Theme.chartGrid,
                    start = Offset(0f, y),
                    end = Offset(size.width, y),
                    strokeWidth = 1f,
                )
            }

            val line = Path()
            val area = Path().apply { moveTo(xFor(points.first().minute), plotHeight) }
            points.forEachIndexed { index, point ->
                val x = xFor(point.minute)
                val y = yFor(point.powerKW)
                if (index == 0) line.moveTo(x, y) else line.lineTo(x, y)
                area.lineTo(x, y)
            }
            area.lineTo(xFor(points.last().minute), plotHeight)
            area.close()

            drawPath(area, Theme.regenGreen.copy(alpha = 0.18f))
            drawPath(line, Theme.regenGreen, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))

            val selection = selected
            if (selection != null) {
                val x = xFor(selection.minute)
                drawLine(
                    color = Theme.textSecondary.copy(alpha = 0.5f),
                    start = Offset(x, 0f),
                    end = Offset(x, plotHeight),
                    strokeWidth = 1f,
                )
                drawCircle(
                    color = Theme.electricCyan,
                    radius = 4.dp.toPx(),
                    center = Offset(x, yFor(selection.powerKW)),
                )
            }
        }

        if (selected != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
                Readout(formatElapsed(selected.minute * 60), "Elapsed")
                Readout(
                    String.format(Locale.US, "%.1f %s", units.powerValue(selected.powerKW), units.powerUnitLabel),
                    "Speed",
                )
                selected.socPct?.let { soc -> Readout(String.format(Locale.US, "%.0f%%", soc), "Battery") }
            }
        } else {
            Text(
                "Drag across the curve to inspect a moment",
                color = Theme.textSecondary,
                fontSize = 10.sp,
            )
        }
    }
}

@Composable
private fun Readout(value: String, label: String) {
    Column {
        Text(value, color = Theme.textPrimary, fontSize = 13.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
        Text(label, color = Theme.textSecondary, fontSize = 10.sp)
    }
}

/** "12 min" or "1 h 05 min", shared with the live charging card. */
fun formatElapsed(seconds: Double): String {
    if (!seconds.isFinite() || seconds <= 0) return "—"
    val totalMinutes = (seconds / 60).toInt()
    val hours = totalMinutes / 60
    val minutes = totalMinutes % 60
    return if (hours > 0) String.format(Locale.US, "%d h %02d min", hours, minutes) else "$minutes min"
}
