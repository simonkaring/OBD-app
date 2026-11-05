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
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlin.math.abs

internal enum class PowerImageFrame(val lightImage: Int, val darkImage: Int) {
    UNKNOWN(R.drawable.power_image_unknown_light, R.drawable.power_image_unknown_dark),
    IDLE(R.drawable.power_image_idle_light, R.drawable.power_image_idle_dark),
    DRAW_LOW(R.drawable.power_image_draw_low_light, R.drawable.power_image_draw_low_dark),
    DRAW_MID(R.drawable.power_image_draw_mid_light, R.drawable.power_image_draw_mid_dark),
    DRAW_HIGH(R.drawable.power_image_draw_high_light, R.drawable.power_image_draw_high_dark),
    REGEN_LOW(R.drawable.power_image_regen_low_light, R.drawable.power_image_regen_low_dark),
    REGEN_MID(R.drawable.power_image_regen_mid_light, R.drawable.power_image_regen_mid_dark),
    REGEN_HIGH(R.drawable.power_image_regen_high_light, R.drawable.power_image_regen_high_dark),
    CHARGING(R.drawable.power_image_charging_light, R.drawable.power_image_charging_dark),
    ENERGY_IN(R.drawable.power_image_energy_in_light, R.drawable.power_image_energy_in_dark),
}

/** Debug-only image experiment, not a calibrated instrument or a claim of car-policy approval. */
internal object PowerImageExperiment {
    private val images = mutableMapOf<Pair<PowerImageFrame, Boolean>, CarIcon>()

    fun frame(state: CompanionState): PowerImageFrame {
        val magnitude = abs(state.metrics[TelemetryMetric.POWER] ?: 0.0)
        return when (powerIndicator(state).second) {
            R.string.companion_grid_draw -> when {
                magnitude < 25 -> PowerImageFrame.DRAW_LOW
                magnitude < 75 -> PowerImageFrame.DRAW_MID
                else -> PowerImageFrame.DRAW_HIGH
            }
            R.string.companion_grid_regen -> when {
                magnitude < 10 -> PowerImageFrame.REGEN_LOW
                magnitude < 30 -> PowerImageFrame.REGEN_MID
                else -> PowerImageFrame.REGEN_HIGH
            }
            R.string.companion_grid_charging -> PowerImageFrame.CHARGING
            R.string.companion_grid_idle -> PowerImageFrame.IDLE
            R.string.companion_grid_energy_in -> PowerImageFrame.ENERGY_IN
            else -> PowerImageFrame.UNKNOWN
        }
    }

    /** Unique resource IDs avoid CarIcon's bitmap equality limitation; at most 20 cached icons. */
    @Synchronized
    fun icon(context: Context, state: CompanionState, darkMode: Boolean): CarIcon =
        images.getOrPut(frame(state) to darkMode) {
            val frame = frame(state)
            CarIcon.Builder(IconCompat.createWithResource(context, if (darkMode) frame.darkImage else frame.lightImage)).build()
        }

    /** Reference asset renderer used only by instrumentation, never during template refreshes. */
    internal fun render(context: Context, frame: PowerImageFrame, darkMode: Boolean): Bitmap {
        val bitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val foreground = if (darkMode) Color.rgb(242, 246, 248) else Color.rgb(28, 37, 43)
        val track = if (darkMode) Color.rgb(78, 89, 98) else Color.rgb(191, 201, 208)
        val drawColor = if (darkMode) Color.rgb(255, 208, 128) else Color.rgb(135, 77, 0)
        val regenColor = if (darkMode) Color.rgb(137, 220, 255) else Color.rgb(0, 91, 127)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = 24f
            color = track
        }
        val arc = RectF(24f, 32f, 168f, 176f)
        canvas.drawArc(arc, 150f, 116f, false, paint)
        canvas.drawArc(arc, 274f, 116f, false, paint)
        // Fixed visual buckets, not a numeric scale; the exact kW stays in host-rendered text.
        val angle = when (frame) {
            PowerImageFrame.DRAW_LOW -> 300f
            PowerImageFrame.DRAW_MID -> 330f
            PowerImageFrame.DRAW_HIGH -> 360f
            PowerImageFrame.REGEN_LOW -> 240f
            PowerImageFrame.REGEN_MID -> 210f
            PowerImageFrame.REGEN_HIGH -> 180f
            PowerImageFrame.IDLE -> 270f
            else -> null
        }
        if (angle != null) {
            paint.color = when {
                angle > 270 -> drawColor
                angle < 270 -> regenColor
                else -> foreground
            }
            if (angle > 270) canvas.drawArc(arc, 274f, angle - 274, false, paint)
            if (angle < 270) canvas.drawArc(arc, angle, 266 - angle, false, paint)
            if (frame == PowerImageFrame.IDLE) canvas.drawArc(arc, 268f, 4f, false, paint)
            // Hub glyph names the direction, so the power dial never reads as a speed or charge dial.
            val hub = when (frame) {
                PowerImageFrame.IDLE -> R.drawable.ic_companion_idle
                PowerImageFrame.REGEN_LOW, PowerImageFrame.REGEN_MID, PowerImageFrame.REGEN_HIGH ->
                    R.drawable.ic_companion_regen
                else -> R.drawable.ic_companion_draw
            }
            drawDialSymbol(context, canvas, hub, foreground)
        } else {
            val symbol = when (frame) {
                PowerImageFrame.CHARGING -> R.drawable.ic_car_charging
                PowerImageFrame.ENERGY_IN -> R.drawable.ic_companion_regen
                else -> R.drawable.ic_companion_unknown
            }
            drawDialSymbol(context, canvas, symbol, foreground, RectF(70f, 78f, 122f, 130f), 255)
        }
        return bitmap
    }
}
