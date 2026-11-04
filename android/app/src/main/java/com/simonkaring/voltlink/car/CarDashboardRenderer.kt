package com.simonkaring.voltlink.car

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import androidx.car.app.model.CarIcon
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.drawable.IconCompat
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Draws a [CarDashboard] the way the phone draws its live telemetry screen — the pack bar over
 * `MetricDial` dials (252° track from 144°, gradient fill, ticks, value, unit and status chip) on
 * dark rounded cards — into one square bitmap, because car templates render host widgets and
 * cannot host Compose.
 *
 * The picture is square and sparse on purpose. A pane template shows its image in a small fixed
 * square slot (about 290 px on the head unit) and centre-crops anything else, and grid or row
 * images shrink to icon size, so this is the only large canvas a car tab gets. Text is sized to
 * stay readable at that slot, which is why number readouts live in host-rendered rows instead.
 * Everything is laid out in a 1024-unit space and scaled to [sizePx].
 *
 * Icons are cached by dashboard: telemetry ticks arrive about once a second, and a value that
 * did not change should not allocate another bitmap.
 */
internal class CarDashboardRenderer(private val sizePx: Int = DEFAULT_SIZE_PX) {
    private val cache = LinkedHashMap<CarDashboard, CarIcon>()

    fun icon(dashboard: CarDashboard): CarIcon {
        cache[dashboard]?.let { return it }
        return render(dashboard).also { icon ->
            if (cache.size >= MAX_CACHED) cache.clear()
            cache[dashboard] = icon
        }
    }

    private fun render(dashboard: CarDashboard): CarIcon {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(sizePx / SPACE, sizePx / SPACE)
        draw(canvas, dashboard)
        return CarIcon.Builder(IconCompat.createWithBitmap(bitmap)).build()
    }

    private fun draw(canvas: Canvas, dashboard: CarDashboard) {
        val bar = dashboard.bar
        val gap = if (bar != null && dashboard.dials.isNotEmpty()) GAP else 0f
        val barH = if (bar != null) BAR_H else 0f
        // Dials take the height the bar leaves, within limits that keep the ring round.
        val dialH = if (dashboard.dials.isEmpty()) 0f else (EXTENT - barH - gap).coerceAtMost(DIAL_MAX_H)
        var top = (SPACE - (barH + gap + dialH)) / 2f

        if (bar != null) {
            drawBar(canvas, RectF(PAD, top, SPACE - PAD, top + BAR_H), bar)
            top += BAR_H + gap
        }
        if (dashboard.dials.isNotEmpty()) {
            val count = dashboard.dials.size
            val cell = (EXTENT - GAP * (count - 1)) / count
            dashboard.dials.forEachIndexed { index, dial ->
                val left = PAD + index * (cell + GAP)
                drawDial(canvas, RectF(left, top, left + cell, top + dialH), dial)
            }
        }
    }

    private fun drawCard(canvas: Canvas, rect: RectF) {
        canvas.drawRoundRect(
            rect,
            CARD_RADIUS,
            CARD_RADIUS,
            paint().apply {
                shader = LinearGradient(
                    0f,
                    rect.top,
                    0f,
                    rect.bottom,
                    ColorUtils.blendARGB(CarDialColors.card, CarDialColors.textPrimary, 0.05f),
                    ColorUtils.blendARGB(CarDialColors.card, 0xFF000000.toInt(), 0.2f),
                    Shader.TileMode.CLAMP,
                )
            },
        )
        canvas.drawRoundRect(
            rect,
            CARD_RADIUS,
            CARD_RADIUS,
            paint().apply {
                style = Paint.Style.STROKE
                strokeWidth = 3f
                color = CarDialColors.cardEdge
            },
        )
    }

    private fun drawBar(canvas: Canvas, rect: RectF, bar: CarBar) {
        drawCard(canvas, rect)
        val left = rect.left + CARD_PAD
        val right = rect.right - CARD_PAD

        val trailing = bar.trailing
        val label = text(46f, CarDialColors.textSecondary, Typeface.create(MEDIUM, Typeface.NORMAL))
        val labelRoom = if (trailing == null) right - left else (right - left) * 0.62f
        canvas.drawText(ellipsize(label, bar.label, labelRoom), left, rect.top + CARD_PAD + 38f, label)
        trailing?.let {
            val temp = text(46f, CarDialColors.textPrimary, Typeface.create(MEDIUM, Typeface.NORMAL), Paint.Align.RIGHT)
            canvas.drawText(it, right, rect.top + CARD_PAD + 38f, temp)
        }

        val percent = text(
            108f,
            if (bar.available) CarDialColors.textPrimary else CarDialColors.textSecondary,
            Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD),
            Paint.Align.RIGHT,
        )
        val centerY = rect.bottom - CARD_PAD - 46f
        canvas.drawText(bar.valueText, right, centerY + 38f, percent)

        val trackRight = right - percent.measureText("100%") - 30f
        val track = RectF(left, centerY - BAR_TRACK_H / 2f, trackRight, centerY + BAR_TRACK_H / 2f)
        val radius = BAR_TRACK_H / 2f
        canvas.drawRoundRect(track, radius, radius, paint().apply { color = CarDialColors.track })

        if (bar.available && bar.fraction > EPSILON) {
            val width = max(track.width() * bar.fraction.toFloat(), BAR_TRACK_H)
            val fill = RectF(left, track.top, left + width, track.bottom)
            val shader = LinearGradient(
                fill.left,
                0f,
                fill.right,
                0f,
                ColorUtils.blendARGB(bar.color, 0xFF000000.toInt(), 0.35f),
                bar.color,
                Shader.TileMode.CLAMP,
            )
            canvas.drawRoundRect(
                fill,
                radius,
                radius,
                paint().apply {
                    this.shader = shader
                    maskFilter = BlurMaskFilter(BAR_TRACK_H * 0.6f, BlurMaskFilter.Blur.NORMAL)
                    alpha = GLOW_ALPHA
                },
            )
            canvas.drawRoundRect(fill, radius, radius, paint().apply { this.shader = shader })
        }

        bar.marks.forEach { mark ->
            val x = track.left + track.width() * mark.toFloat().coerceIn(0f, 1f)
            canvas.drawRoundRect(
                RectF(x - 4f, track.top - 12f, x + 4f, track.bottom + 12f),
                4f,
                4f,
                paint().apply { color = CarDialColors.textPrimary },
            )
        }
    }

    private fun drawDial(canvas: Canvas, rect: RectF, dial: CarDial) {
        drawCard(canvas, rect)
        // The chip sits under the ring, so the ring and the chip share the card's height.
        val chipBlock = if (dial.status != null) CHIP_BLOCK else 0f
        val diameter = min(rect.width() - DIAL_PAD * 2, rect.height() - DIAL_PAD * 2 - chipBlock)
        val stroke = diameter * STROKE_FRACTION
        val cx = rect.centerX()
        val cy = rect.centerY() - chipBlock / 2f
        val arc = RectF(
            cx - diameter / 2f + stroke / 2f,
            cy - diameter / 2f + stroke / 2f,
            cx + diameter / 2f - stroke / 2f,
            cy + diameter / 2f - stroke / 2f,
        )

        canvas.drawArc(arc, START_ANGLE, SWEEP_ANGLE, false, ring(CarDialColors.track, stroke))
        drawTicks(canvas, arc, stroke)
        if (dial.available) drawFill(canvas, arc, stroke, dial)
        drawDialText(canvas, cx, cy, diameter, dial)
        dial.status?.let { drawChip(canvas, rect, cy + diameter / 2f + CHIP_BLOCK * 0.5f, it, dial) }
    }

    private fun drawFill(canvas: Canvas, arc: RectF, stroke: Float, dial: CarDial) {
        val start: Float
        val sweep: Float
        val head: Float
        if (dial.bidirectional) {
            val low = min(0.0, dial.fraction)
            val high = max(0.0, dial.fraction)
            if (high - low <= EPSILON) return
            start = 90f + ((0.5 + low * 0.35) * 360.0).toFloat()
            sweep = ((high - low) * 0.35 * 360.0).toFloat()
            head = if (dial.fraction >= 0) start + sweep else start
        } else {
            if (dial.fraction <= EPSILON) return
            start = START_ANGLE
            sweep = (SWEEP_ANGLE * dial.fraction).toFloat()
            head = start + sweep
        }

        val shader = LinearGradient(
            arc.left,
            0f,
            arc.right,
            0f,
            dial.colors.toIntArray(),
            null,
            Shader.TileMode.CLAMP,
        )
        canvas.drawArc(
            arc,
            start,
            sweep,
            false,
            ring(dial.colors.first(), stroke).apply {
                this.shader = shader
                maskFilter = BlurMaskFilter(stroke * 0.7f, BlurMaskFilter.Blur.NORMAL)
                alpha = GLOW_ALPHA
            },
        )
        canvas.drawArc(arc, start, sweep, false, ring(dial.colors.first(), stroke).apply { this.shader = shader })

        val angle = Math.toRadians(head.toDouble())
        canvas.drawCircle(
            arc.centerX() + (cos(angle) * arc.width() / 2f).toFloat(),
            arc.centerY() + (sin(angle) * arc.width() / 2f).toFloat(),
            stroke * 0.2f,
            paint().apply { color = HEAD },
        )
    }

    /** Five evenly spaced ticks along the arc, the way the phone's dial is indexed. */
    private fun drawTicks(canvas: Canvas, arc: RectF, stroke: Float) {
        val tick = paint().apply {
            color = TICK
            strokeWidth = 4f
            strokeCap = Paint.Cap.ROUND
        }
        val radius = arc.width() / 2f
        val inner = radius - stroke * 0.95f
        val outer = radius - stroke * 0.20f
        repeat(TICKS) { index ->
            val angle = Math.toRadians((START_ANGLE + SWEEP_ANGLE * index / (TICKS - 1)).toDouble())
            canvas.drawLine(
                arc.centerX() + (cos(angle) * inner).toFloat(),
                arc.centerY() + (sin(angle) * inner).toFloat(),
                arc.centerX() + (cos(angle) * outer).toFloat(),
                arc.centerY() + (sin(angle) * outer).toFloat(),
                tick,
            )
        }
    }

    private fun drawDialText(canvas: Canvas, cx: Float, cy: Float, diameter: Float, dial: CarDial) {
        val value = text(
            diameter * 0.32f,
            when {
                !dial.available -> CarDialColors.textSecondary
                dial.negative -> CarDialColors.green
                else -> CarDialColors.textPrimary
            },
            Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD),
            Paint.Align.CENTER,
        )
        fit(value, dial.valueText, diameter * 0.60f, diameter * 0.14f)

        val unitSize = diameter * 0.10f
        val valueHeight = value.textSize * 0.72f
        val unitBlock = if (dial.unitText != null) unitSize * 1.6f else 0f
        val valueBaseline = cy - (valueHeight + unitBlock) / 2f + valueHeight - diameter * 0.01f
        canvas.drawText(dial.valueText, cx, valueBaseline, value)

        dial.unitText?.let {
            val unit = text(unitSize, CarDialColors.textSecondary, Typeface.SANS_SERIF, Paint.Align.CENTER)
            canvas.drawText(it, cx, valueBaseline + unitSize * 1.45f, unit)
        }
    }

    /** The phone dial's status chip: the metric name, or Regen/Draw/Idle for power. */
    private fun drawChip(canvas: Canvas, rect: RectF, centerY: Float, status: String, dial: CarDial) {
        val accent = when {
            !dial.available -> CarDialColors.textSecondary
            dial.negative -> CarDialColors.green
            else -> CarDialColors.cyan
        }
        val chip = text(CHIP_TEXT, accent, Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD), Paint.Align.CENTER)
        fit(chip, status, rect.width() - DIAL_PAD * 2 - CHIP_TEXT * 1.6f, CHIP_TEXT * 0.6f)
        val half = chip.measureText(status) / 2f + CHIP_TEXT * 0.8f
        val pill = RectF(
            rect.centerX() - half,
            centerY - CHIP_TEXT * 0.95f,
            rect.centerX() + half,
            centerY + CHIP_TEXT * 0.95f,
        )
        canvas.drawRoundRect(
            pill,
            CHIP_TEXT,
            CHIP_TEXT,
            paint().apply { color = ColorUtils.setAlphaComponent(accent, CHIP_ALPHA) },
        )
        canvas.drawText(status, rect.centerX(), centerY + chip.textSize * 0.35f, chip)
    }

    private fun paint() = Paint(Paint.ANTI_ALIAS_FLAG)

    private fun ring(color: Int, stroke: Float) = paint().apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        this.color = color
    }

    private fun text(
        size: Float,
        color: Int,
        typeface: Typeface,
        align: Paint.Align = Paint.Align.LEFT,
    ) = paint().apply {
        textSize = size
        this.color = color
        this.typeface = typeface
        textAlign = align
    }

    /** Shrinks the text until it fits [maxWidth], the way the Compose dial keeps its number on one line. */
    private fun fit(paint: Paint, text: String, maxWidth: Float, minSize: Float) {
        while (paint.measureText(text) > maxWidth && paint.textSize > minSize) paint.textSize *= 0.92f
    }

    private fun ellipsize(paint: Paint, text: String, maxWidth: Float): String =
        TextUtils.ellipsize(text, TextPaint(paint), maxWidth, TextUtils.TruncateAt.END).toString()

    private companion object {
        // A pane template shows this in a fixed square slot, so draw well above its size.
        const val DEFAULT_SIZE_PX = 768
        const val MAX_CACHED = 8

        // Layout space; the renderer scales it to the bitmap.
        const val SPACE = 1024f
        const val PAD = 6f
        const val EXTENT = SPACE - PAD * 2
        const val GAP = 16f
        const val CARD_RADIUS = 48f
        const val CARD_PAD = 40f
        const val BAR_H = 268f
        const val BAR_TRACK_H = 58f
        const val DIAL_MAX_H = 760f
        const val DIAL_PAD = 34f
        const val CHIP_TEXT = 58f
        const val CHIP_BLOCK = CHIP_TEXT * 2.4f

        const val START_ANGLE = 144f
        const val SWEEP_ANGLE = 252f
        const val STROKE_FRACTION = 0.09f
        const val TICKS = 5
        const val EPSILON = 0.001
        const val GLOW_ALPHA = 110
        const val CHIP_ALPHA = 51
        const val TICK = 0x33FFFFFF
        const val HEAD = 0xE6FFFFFF.toInt()
        const val MEDIUM = "sans-serif-medium"
    }
}
