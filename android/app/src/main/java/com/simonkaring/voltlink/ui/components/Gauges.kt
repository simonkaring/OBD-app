package com.simonkaring.voltlink.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.ui.theme.Theme
import java.util.Locale

/** Formats [value] with the metric's decimal places, rendering an em dash when unavailable. */
fun formatMetric(value: Double, metric: TelemetryMetric, isUnavailable: Boolean = false): String {
    if (isUnavailable || !value.isFinite()) return "--"
    return String.format(Locale.US, "%.${metric.decimalPlaces}f", value)
}

/**
 * Arc dial matching the iOS `MetricDialView`: a 252° track with an optional bidirectional
 * fill for power draw vs. regen.
 */
@Composable
fun MetricDial(
    value: Double,
    range: ClosedFloatingPointRange<Double>,
    unit: String,
    label: String,
    modifier: Modifier = Modifier,
    bidirectional: Boolean = false,
    brush: Brush = Theme.powerBrush,
    isUnavailable: Boolean = false,
    statusOverride: String? = null,
    onTap: (() -> Unit)? = null,
) {
    val progress = when {
        bidirectional -> if (value >= 0) {
            (value / maxOf(range.endInclusive, 0.0001)).coerceIn(0.0, 1.0)
        } else {
            (value / maxOf(kotlin.math.abs(range.start), 0.0001)).coerceIn(-1.0, 0.0)
        }
        else -> {
            val span = range.endInclusive - range.start
            if (span <= 0) 0.0 else ((value - range.start) / span).coerceIn(0.0, 1.0)
        }
    }
    val animated by animateFloatAsState(progress.toFloat(), animationSpec = spring(dampingRatio = 1f), label = "dial")
    val negative = bidirectional && value < 0
    val status = statusOverride ?: when {
        !bidirectional -> label
        value < -0.5 -> "Regen"
        value > 5.0 -> "Draw"
        else -> "Idle"
    }
    val statusColor = if (negative) Theme.regenGreen else Theme.gaugeCyan

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val stroke = maxOf(6.dp.toPx(), size.minDimension * 0.09f)
            val inset = stroke / 2 + 2.dp.toPx()
            val diameter = maxOf(10f, size.minDimension - inset * 2)
            val topLeft = Offset((size.width - diameter) / 2, (size.height - diameter) / 2)
            val arcSize = Size(diameter, diameter)

            drawArc(
                color = Theme.trackBackground,
                startAngle = 144f,
                sweepAngle = 252f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
            if (!isUnavailable) {
                if (bidirectional) {
                    val low = minOf(0f, animated)
                    val high = maxOf(0f, animated)
                    drawArc(
                        brush = brush,
                        startAngle = 90f + (0.5f + low * 0.35f) * 360f,
                        sweepAngle = (high - low) * 0.35f * 360f,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                    )
                } else {
                    drawArc(
                        brush = brush,
                        startAngle = 144f,
                        sweepAngle = 252f * animated,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                    )
                }
            }
        }

        MetricDialText(
            valueText = if (isUnavailable) "--" else formatMetric(value, TelemetryMetric.SPEED).let {
                if (value >= 100) String.format(Locale.US, "%.0f", kotlin.math.abs(value)) else String.format(Locale.US, "%.1f", kotlin.math.abs(value)).removeSuffix(".0")
            },
            unit = unit,
            status = if (isUnavailable) label else status,
            statusColor = if (isUnavailable) Theme.textSecondary else statusColor,
            valueColor = if (negative) Theme.regenGreen else Theme.textPrimary,
            statusBackground = statusColor.copy(alpha = 0.2f),
        )
    }
}

@Composable
private fun MetricDialText(
    valueText: String,
    unit: String,
    status: String,
    statusColor: Color,
    valueColor: Color,
    statusBackground: Color,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = valueText,
                color = valueColor,
                fontSize = 34.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
            Spacer(Modifier.width(2.dp))
            Text(text = unit, color = Theme.textSecondary, fontSize = 14.sp, modifier = Modifier.padding(bottom = 4.dp))
        }
        Text(
            text = status,
            color = statusColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .background(statusBackground, RoundedCornerShape(6.dp))
                .padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

/** Horizontal bar gauge with a rounded track, used for compact metrics. */
@Composable
fun MetricBar(
    value: Double,
    range: ClosedFloatingPointRange<Double>,
    unit: String,
    label: String,
    modifier: Modifier = Modifier,
    brush: Brush = Theme.socBrush,
    isUnavailable: Boolean = false,
) {
    val span = range.endInclusive - range.start
    val fraction = if (span <= 0) 0f else ((value - range.start) / span).coerceIn(0.0, 1.0).toFloat()
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(label, color = Theme.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f), maxLines = 1)
            Text(
                text = if (isUnavailable) "-- $unit" else "${String.format(Locale.US, "%.0f", value)} $unit",
                color = Theme.textPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Theme.trackBackground),
        ) {
            if (!isUnavailable) {
                Box(
                    Modifier
                        .fillMaxWidth(fraction)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(4.dp))
                        .background(brush),
                )
            }
        }
    }
}

/** Compact number card for secondary metrics. */
@Composable
fun NumericTile(
    value: Double,
    unit: String,
    label: String,
    metric: TelemetryMetric,
    modifier: Modifier = Modifier,
    isUnavailable: Boolean = false,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, color = Theme.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = if (isUnavailable) "--" else formatMetric(value, metric),
                color = Theme.textPrimary,
                fontSize = 24.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
            Spacer(Modifier.width(3.dp))
            Text(unit, color = Theme.textSecondary, fontSize = 12.sp, modifier = Modifier.padding(bottom = 2.dp))
        }
    }
}

/** High-voltage pack bar with charging colouring and a start-of-charge tick. */
@Composable
fun BatteryLevelBar(
    socPct: Double?,
    batteryTempLabel: String?,
    isCharging: Boolean,
    startSocPct: Double? = null,
    modifier: Modifier = Modifier,
) {
    val barColor = when {
        socPct == null -> Theme.textSecondary
        isCharging -> Theme.regenGreen
        socPct < 20.0 -> Theme.criticalRed
        socPct < 40.0 -> Theme.highPowerAmber
        else -> Theme.gaugeCyan
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(if (isCharging) R.string.gauges_hv_battery_charging else R.string.gauges_hv_battery),
                color = Theme.textSecondary,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            if (batteryTempLabel != null) {
                Text(
                    stringResource(R.string.gauges_hv_prefix, batteryTempLabel),
                    color = Theme.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier
                    .weight(1f)
                    .height(10.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(Theme.trackBackground),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth((socPct ?: 0.0).coerceIn(0.0, 100.0).toFloat() / 100f)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(5.dp))
                        .background(barColor),
                )
                if (startSocPct != null) {
                    Box(
                        Modifier
                            .fillMaxWidth((startSocPct.coerceIn(0.0, 100.0) / 100.0).toFloat())
                            .align(Alignment.CenterEnd)
                            .offset(x = 1.dp)
                            .width(2.dp)
                            .fillMaxHeight()
                            .background(Theme.textPrimary),
                    )
                }
            }
            Text(
                text = socPct?.let { String.format(Locale.US, "%.0f%%", it) } ?: "—",
                color = Theme.textPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (startSocPct != null && socPct != null && socPct - startSocPct >= 0.5) {
            Text(
                text = stringResource(R.string.gauges_charging_started, startSocPct, socPct - startSocPct),
                color = Theme.textSecondary,
                fontSize = 12.sp,
            )
        }
    }
}

/** Diameter-preserving inset used by the dial tiles. */
val DialHeight: Dp = 176.dp
