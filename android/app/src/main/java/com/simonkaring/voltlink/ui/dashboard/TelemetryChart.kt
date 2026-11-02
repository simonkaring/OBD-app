package com.simonkaring.voltlink.ui.dashboard

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.ui.theme.Theme
import kotlin.math.abs

/** Rolling power + speed stream, mirroring the iOS Swift Charts tile. */
@Composable
fun LiveTelemetryChart(
    history: List<TelemetrySnapshot>,
    modifier: Modifier = Modifier,
    isUnavailable: Boolean = false,
) {
    val powers = history.map { it.powerKW }
    val speeds = history.map { it.speedKmH }
    val maxPower = maxOf(1.0, powers.maxOfOrNull { abs(it) } ?: 1.0)
    val maxSpeed = maxOf(1.0, speeds.maxOfOrNull { it } ?: 1.0)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Live telemetry", color = Theme.textPrimary, fontSize = 14.sp, modifier = Modifier.weight(1f))
            LegendDot("Power", Theme.gaugeCyan)
            Spacer(Modifier.width(10.dp))
            LegendDot("Speed", Theme.regenGreen)
        }
        Box(modifier = Modifier.fillMaxWidth().height(150.dp)) {
            if (history.size < 2 || isUnavailable) {
                Text(
                    text = if (isUnavailable) "Waiting for vehicle data" else "Collecting samples…",
                    color = Theme.textSecondary,
                    fontSize = 12.sp,
                    modifier = Modifier.align(Alignment.Center),
                )
            } else {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    // Grid: three horizontal hairlines plus a zero baseline for power.
                    repeat(4) { index ->
                        val y = size.height * index / 3f
                        drawLine(
                            color = Theme.chartGrid,
                            start = Offset(0f, y),
                            end = Offset(size.width, y),
                            strokeWidth = 1f,
                        )
                    }

                    fun pathFor(values: List<Double>, maxValue: Double, center: Boolean): Path {
                        val path = Path()
                        val stepX = size.width / (values.size - 1).coerceAtLeast(1)
                        values.forEachIndexed { index, value ->
                            val fraction = if (center) {
                                0.5 - (value / maxValue) * 0.45
                            } else {
                                0.95 - (value / maxValue) * 0.9
                            }
                            val point = Offset(index * stepX, (fraction * size.height).toFloat())
                            if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
                        }
                        return path
                    }

                    drawPath(
                        path = pathFor(powers, maxPower, center = true),
                        color = Theme.gaugeCyan,
                        style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round),
                    )
                    drawPath(
                        path = pathFor(speeds, maxSpeed, center = false),
                        color = Theme.regenGreen,
                        style = Stroke(width = 2.0.dp.toPx(), cap = StrokeCap.Round),
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = String.format(java.util.Locale.US, "%.0f kW", powers.lastOrNull() ?: 0.0),
                color = Theme.gaugeCyan,
                fontSize = 12.sp,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = String.format(java.util.Locale.US, "%.0f km/h", speeds.lastOrNull() ?: 0.0),
                color = Theme.regenGreen,
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun LegendDot(label: String, color: androidx.compose.ui.graphics.Color) {
    Box(Modifier.size(7.dp).clip(CircleShape).background(color))
    Spacer(Modifier.width(4.dp))
    Text(label, color = Theme.textSecondary, fontSize = 11.sp)
}
