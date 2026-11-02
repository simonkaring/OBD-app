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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.theme.Theme
import java.util.Locale
import kotlin.math.abs

/** Rolling multi-metric stream, mirroring the iOS Swift Charts tile. */
@Composable
fun LiveTelemetryChart(
    history: List<TelemetrySnapshot>,
    units: UnitPrefs,
    series: List<TelemetryMetric> = listOf(TelemetryMetric.POWER, TelemetryMetric.SPEED),
    modifier: Modifier = Modifier,
    isUnavailable: Boolean = false,
    title: String? = null,
) {
    // Stable colours per position so reordering a chart's series keeps its legend readable.
    val colors = series.mapIndexed { index, _ -> seriesColor(index) }
    val values = series.map { metric -> history.map { units.value(metric, it) } }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                title ?: stringResource(R.string.chart_title),
                color = Theme.textPrimary,
                fontSize = 14.sp,
                modifier = Modifier.weight(1f),
            )
            series.forEachIndexed { index, metric ->
                if (index > 0) Spacer(Modifier.width(10.dp))
                LegendDot(metric.displayName, colors[index])
            }
        }
        Box(modifier = Modifier.fillMaxWidth().height(150.dp)) {
            if (history.size < 2 || isUnavailable || values.all { it.isEmpty() }) {
                Column(
                    modifier = Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = if (isUnavailable) {
                            stringResource(R.string.chart_waiting)
                        } else {
                            stringResource(R.string.chart_empty_title)
                        },
                        color = Theme.textPrimary,
                        fontSize = 13.sp,
                    )
                    if (!isUnavailable) {
                        Text(
                            text = stringResource(R.string.chart_collecting),
                            color = Theme.textSecondary,
                            fontSize = 11.sp,
                        )
                    }
                }
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

                    values.forEachIndexed { index, samples ->
                        val maxValue = maxOf(1.0, samples.maxOfOrNull { abs(it) } ?: 1.0)
                        val centered = series[index] == TelemetryMetric.POWER
                        val path = Path()
                        val stepX = size.width / (samples.size - 1).coerceAtLeast(1)
                        samples.forEachIndexed { sampleIndex, value ->
                            val fraction = if (centered) {
                                0.5 - (value / maxValue) * 0.45
                            } else {
                                0.95 - (value / maxValue) * 0.9
                            }
                            val point = Offset(sampleIndex * stepX, (fraction * size.height).toFloat())
                            if (sampleIndex == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
                        }
                        drawPath(
                            path = path,
                            color = colors[index],
                            style = Stroke(width = if (index == 0) 2.5.dp.toPx() else 2.0.dp.toPx(), cap = StrokeCap.Round),
                        )
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            series.forEachIndexed { index, metric ->
                if (index > 0) Spacer(Modifier.width(14.dp))
                Text(
                    text = String.format(
                        Locale.US,
                        "%.${metric.decimalPlaces}f %s",
                        units.value(metric, history.lastOrNull() ?: TelemetrySnapshot()),
                        units.unit(metric),
                    ),
                    color = colors[index],
                    fontSize = 12.sp,
                )
            }
        }
    }
}

private fun seriesColor(index: Int): Color = when (index % 3) {
    0 -> Theme.gaugeCyan
    1 -> Theme.regenGreen
    else -> Theme.highPowerAmber
}

@Composable
private fun LegendDot(label: String, color: Color) {
    Box(Modifier.size(7.dp).clip(CircleShape).background(color))
    Spacer(Modifier.width(4.dp))
    Text(label, color = Theme.textSecondary, fontSize = 11.sp)
}
