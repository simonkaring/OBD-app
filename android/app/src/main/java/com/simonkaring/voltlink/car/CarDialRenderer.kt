package com.simonkaring.voltlink.car

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import androidx.car.app.model.CarIcon
import androidx.core.graphics.drawable.IconCompat
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Draws a [CarDial] the way the phone draws `MetricDial` — a 252° track from 144°, a gradient
 * fill, tick marks and the value with its unit in the middle — into a bitmap, because car
 * templates render host widgets and cannot host Compose.
 *
 * The default size is deliberately large: a pane template shows this as the hero picture of a
 * tab, so it is drawn at 768 px and let the host scale it down, which keeps the ring crisp.
 *
 * Icons are cached by [CarDial.key]: telemetry ticks arrive about once a second, and a value that
 * did not change should not allocate another bitmap.
 */
internal class CarDialRenderer(private val sizePx: Int = DEFAULT_SIZE_PX) {
    private val cache = LinkedHashMap<String, CarIcon>()

    fun icon(dial: CarDial): CarIcon {
        cache[dial.key]?.let { return it }
        return render(dial).also { icon ->
            if (cache.size >= MAX_CACHED) cache.clear()
            cache[dial.key] = icon
        }
    }

    private fun render(dial: CarDial): CarIcon {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val center = sizePx / 2f

        // A dark disc with a soft centre glow, so the gauge reads as a crafted instrument on the
        // host's own (light or dark) surface instead of a flat icon.
        canvas.drawCircle(
            center,
            center,
            sizePx / 2f,
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    center,
                    center,
                    sizePx / 2f,
                    intArrayOf(GLOW_CENTER, BACKDROP),
                    floatArrayOf(0f, 0.85f),
                    Shader.TileMode.CLAMP,
                )
            },
        )

        val stroke = sizePx * STROKE_FRACTION
        val inset = stroke / 2f + sizePx * 0.06f
        val arc = RectF(inset, inset, sizePx - inset, sizePx - inset)

        canvas.drawArc(arc, START_ANGLE, SWEEP_ANGLE, false, ringPaint(CarDialColors.track, stroke))
        drawTicks(canvas, arc)

        if (dial.available) {
            val fill = ringPaint(dial.colors.first(), stroke).apply {
                shader = sweepGradient(dial)
            }
            if (dial.bidirectional) {
                val low = min(0.0, dial.fraction)
                val high = max(0.0, dial.fraction)
                if (high - low > EPSILON) {
                    canvas.drawArc(
                        arc,
                        90f + ((0.5 + low * 0.35) * 360.0).toFloat(),
                        ((high - low) * 0.35 * 360.0).toFloat(),
                        false,
                        fill,
                    )
                }
            } else if (dial.fraction > EPSILON) {
                canvas.drawArc(arc, START_ANGLE, (SWEEP_ANGLE * dial.fraction).toFloat(), false, fill)
            }
        }

        drawLabels(canvas, dial)
        return CarIcon.Builder(IconCompat.createWithBitmap(bitmap)).build()
    }

    /** Five evenly spaced ticks along the arc, the way the phone's dial is indexed. */
    private fun drawTicks(canvas: Canvas, arc: RectF) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = TICK
            strokeWidth = sizePx * 0.008f
            strokeCap = Paint.Cap.ROUND
        }
        val radius = arc.width() / 2f
        val cx = arc.centerX()
        val cy = arc.centerY()
        val inner = radius - sizePx * STROKE_FRACTION * 0.95f
        val outer = radius - sizePx * STROKE_FRACTION * 0.20f
        repeat(TICKS) { index ->
            val angle = Math.toRadians((START_ANGLE + SWEEP_ANGLE * index / (TICKS - 1)).toDouble())
            canvas.drawLine(
                cx + (cos(angle) * inner).toFloat(),
                cy + (sin(angle) * inner).toFloat(),
                cx + (cos(angle) * outer).toFloat(),
                cy + (sin(angle) * outer).toFloat(),
                paint,
            )
        }
    }

    private fun sweepGradient(dial: CarDial): Shader = LinearGradient(
        0f,
        0f,
        sizePx.toFloat(),
        0f,
        dial.colors.toIntArray(),
        null,
        Shader.TileMode.CLAMP,
    )

    private fun ringPaint(color: Int, stroke: Float): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        this.color = color
    }

    private fun drawLabels(canvas: Canvas, dial: CarDial) {
        val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            color = when {
                !dial.available -> CarDialColors.textSecondary
                dial.negative -> CarDialColors.green
                else -> CarDialColors.textPrimary
            }
        }
        val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
            color = CarDialColors.textSecondary
            textSize = sizePx * 0.10f
        }

        // Shrink the number until it fits inside the ring, the way the Compose dial keeps it on
        // one line.
        var valueSize = sizePx * 0.30f
        valuePaint.textSize = valueSize
        val maxWidth = sizePx * 0.52f
        while (valuePaint.measureText(dial.valueText) > maxWidth && valueSize > sizePx * 0.10f) {
            valueSize *= 0.92f
            valuePaint.textSize = valueSize
        }

        val centerY = sizePx / 2f
        val unit = dial.unitText
        val valueBaseline = if (unit == null) {
            centerY + valueSize * 0.35f
        } else {
            centerY + valueSize * 0.24f
        }
        canvas.drawText(dial.valueText, sizePx / 2f, valueBaseline, valuePaint)
        if (unit != null) {
            canvas.drawText(unit, sizePx / 2f, centerY + sizePx * 0.15f, unitPaint)
        }
    }

    private companion object {
        // A pane template shows this as the hero picture, so draw well above the largest slot.
        const val DEFAULT_SIZE_PX = 768
        const val MAX_CACHED = 8
        const val START_ANGLE = 144f
        const val SWEEP_ANGLE = 252f
        const val STROKE_FRACTION = 0.085f
        const val TICKS = 5
        const val EPSILON = 0.001
        const val BACKDROP = 0xFF141416.toInt()
        const val GLOW_CENTER = 0xFF232326.toInt()
        const val TICK = 0x33FFFFFF
    }
}
