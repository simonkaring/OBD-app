package com.simonkaring.voltlink.companion

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.car.app.model.CarIcon
import androidx.core.graphics.drawable.IconCompat
import com.simonkaring.voltlink.R
import kotlin.math.ceil

internal enum class SpeedImageFrame(val lightImage: Int, val darkImage: Int) {
    UNKNOWN(R.drawable.speed_image_unknown_light, R.drawable.speed_image_unknown_dark),
    STOPPED(R.drawable.speed_image_stopped_light, R.drawable.speed_image_stopped_dark),
    SPEED_20(R.drawable.speed_image_speed_20_light, R.drawable.speed_image_speed_20_dark),
    SPEED_40(R.drawable.speed_image_speed_40_light, R.drawable.speed_image_speed_40_dark),
    SPEED_60(R.drawable.speed_image_speed_60_light, R.drawable.speed_image_speed_60_dark),
    SPEED_80(R.drawable.speed_image_speed_80_light, R.drawable.speed_image_speed_80_dark),
    SPEED_100(R.drawable.speed_image_speed_100_light, R.drawable.speed_image_speed_100_dark),
    SPEED_120(R.drawable.speed_image_speed_120_light, R.drawable.speed_image_speed_120_dark),
    SPEED_140(R.drawable.speed_image_speed_140_light, R.drawable.speed_image_speed_140_dark),
    SPEED_160(R.drawable.speed_image_speed_160_light, R.drawable.speed_image_speed_160_dark),
}

/** Debug-only coarse illustration; exact km/h remains native text, not a vehicle speed limit. */
internal object SpeedImageExperiment {
    private val images = mutableMapOf<Pair<SpeedImageFrame, Boolean>, CarIcon>()

    fun frame(speed: Double?): SpeedImageFrame = when {
        speed == null || !speed.isFinite() || speed < 0 -> SpeedImageFrame.UNKNOWN
        speed == 0.0 -> SpeedImageFrame.STOPPED
        else -> SpeedImageFrame.entries[1 + ceil(speed.coerceAtMost(160.0) / 20).toInt()]
    }

    // Distinct resources preserve CarIcon equality across frames and host themes.
    @Synchronized
    fun icon(context: Context, speed: Double?, darkMode: Boolean): CarIcon =
        images.getOrPut(frame(speed) to darkMode) {
            val frame = frame(speed)
            CarIcon.Builder(IconCompat.createWithResource(context, if (darkMode) frame.darkImage else frame.lightImage)).build()
        }

    /** Reference asset renderer used only by instrumentation, never during template refreshes. */
    internal fun render(context: Context, frame: SpeedImageFrame, darkMode: Boolean): Bitmap = renderDial(
        context, if (frame == SpeedImageFrame.UNKNOWN) null else (frame.ordinal - 1) / 8f, darkMode,
        R.drawable.ic_car_telemetry,
    )
}

/**
 * Shared reference renderer for the matching Speed and Charging assets; never used by templates.
 * [accent] overrides the value colour, which lets the Charging dial read green like the phone UI.
 */
internal fun renderDial(context: Context, fraction: Float?, darkMode: Boolean, glyph: Int, accent: Int? = null): Bitmap {
    val bitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeWidth = 24f
        color = if (darkMode) Color.rgb(78, 89, 98) else Color.rgb(191, 201, 208)
    }
    val arc = RectF(24f, 32f, 168f, 176f)
    val foreground = if (darkMode) Color.rgb(242, 246, 248) else Color.rgb(28, 37, 43)
    canvas.drawArc(arc, 150f, 240f, false, paint)
    paint.color = accent ?: foreground
    when (fraction) {
        null -> drawDialSymbol(context, canvas, R.drawable.ic_companion_unknown, foreground,
            RectF(70f, 78f, 122f, 130f), 255)
        0f -> canvas.drawArc(arc, 150f, 1f, false, paint)
        else -> canvas.drawArc(arc, 150f, fraction * 240f, false, paint)
    }
    // The hub names the quantity, so the speed and charge dials differ at a glance.
    if (fraction != null) drawDialSymbol(context, canvas, glyph, paint.color)
    return bitmap
}

/**
 * Tinted vector glyph inside a dial. The hub box is centred and kept small so the arc stays the
 * dominant shape; [alpha] lets the identity glyph sit behind the value arcs.
 */
internal fun drawDialSymbol(
    context: Context,
    canvas: Canvas,
    symbol: Int,
    color: Int,
    bounds: RectF = RectF(78f, 86f, 114f, 122f),
    alpha: Int = 191,
) {
    requireNotNull(context.getDrawable(symbol)).mutate().apply {
        setTint(color)
        this.alpha = alpha
        setBounds(bounds.left.toInt(), bounds.top.toInt(), bounds.right.toInt(), bounds.bottom.toInt())
        draw(canvas)
    }
}
