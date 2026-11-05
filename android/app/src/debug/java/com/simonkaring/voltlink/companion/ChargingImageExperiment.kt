package com.simonkaring.voltlink.companion

import android.content.Context
import androidx.car.app.model.CarIcon
import androidx.compose.ui.graphics.toArgb
import androidx.core.graphics.drawable.IconCompat
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.ui.theme.Theme
import kotlin.math.floor

/**
 * Coarse dial steps only: 10% SOC or 20 kW, not a vehicle-calibrated charging limit.
 * [fraction] drives the arc. [IDLE] shares the empty arc with [LEVEL_0] but stays neutral, so
 * "nothing is flowing" never looks green.
 */
internal enum class ChargingImageFrame(val lightImage: Int, val darkImage: Int, val fraction: Float?) {
    UNKNOWN(R.drawable.charging_image_unknown_light, R.drawable.charging_image_unknown_dark, null),
    IDLE(R.drawable.charging_image_idle_light, R.drawable.charging_image_idle_dark, 0f),
    LEVEL_0(R.drawable.charging_image_level_0_light, R.drawable.charging_image_level_0_dark, 0f),
    LEVEL_1(R.drawable.charging_image_level_1_light, R.drawable.charging_image_level_1_dark, 0.1f),
    LEVEL_2(R.drawable.charging_image_level_2_light, R.drawable.charging_image_level_2_dark, 0.2f),
    LEVEL_3(R.drawable.charging_image_level_3_light, R.drawable.charging_image_level_3_dark, 0.3f),
    LEVEL_4(R.drawable.charging_image_level_4_light, R.drawable.charging_image_level_4_dark, 0.4f),
    LEVEL_5(R.drawable.charging_image_level_5_light, R.drawable.charging_image_level_5_dark, 0.5f),
    LEVEL_6(R.drawable.charging_image_level_6_light, R.drawable.charging_image_level_6_dark, 0.6f),
    LEVEL_7(R.drawable.charging_image_level_7_light, R.drawable.charging_image_level_7_dark, 0.7f),
    LEVEL_8(R.drawable.charging_image_level_8_light, R.drawable.charging_image_level_8_dark, 0.8f),
    LEVEL_9(R.drawable.charging_image_level_9_light, R.drawable.charging_image_level_9_dark, 0.9f),
    LEVEL_10(R.drawable.charging_image_level_10_light, R.drawable.charging_image_level_10_dark, 1f),
    ;

    /** Green only while the car is actually charging; idle and unknown stay neutral grey. */
    val accent: Int? get() = if (this == IDLE || this == UNKNOWN) null else Theme.regenGreen.toArgb()
}

internal object ChargingImageExperiment {
    private val images = mutableMapOf<Pair<ChargingImageFrame, Boolean>, CarIcon>()
    private val levels = listOf(
        ChargingImageFrame.LEVEL_0, ChargingImageFrame.LEVEL_1, ChargingImageFrame.LEVEL_2,
        ChargingImageFrame.LEVEL_3, ChargingImageFrame.LEVEL_4, ChargingImageFrame.LEVEL_5,
        ChargingImageFrame.LEVEL_6, ChargingImageFrame.LEVEL_7, ChargingImageFrame.LEVEL_8,
        ChargingImageFrame.LEVEL_9, ChargingImageFrame.LEVEL_10,
    )

    fun socFrame(soc: Double?): ChargingImageFrame = level(soc?.takeIf { it <= 100 }, 10.0)

    /**
     * Absent, invalid or zero power means nothing is flowing yet: the grey idle bolt reads as
     * "charging-capable", where a question mark read as a broken reading.
     */
    fun powerFrame(powerKW: Double?): ChargingImageFrame =
        if (powerKW == null || !powerKW.isFinite() || powerKW <= 0) ChargingImageFrame.IDLE
        else level(powerKW, 20.0)

    private fun level(value: Double?, step: Double): ChargingImageFrame {
        if (value == null || !value.isFinite() || value < 0) return ChargingImageFrame.UNKNOWN
        return levels[floor((value / step).coerceAtMost(10.0)).toInt()]
    }

    @Synchronized
    fun icon(context: Context, frame: ChargingImageFrame, darkMode: Boolean): CarIcon =
        images.getOrPut(frame to darkMode) {
            CarIcon.Builder(IconCompat.createWithResource(context, if (darkMode) frame.darkImage else frame.lightImage)).build()
        }

    internal fun render(context: Context, frame: ChargingImageFrame, darkMode: Boolean) = renderDial(
        context, frame.fraction, darkMode, R.drawable.ic_car_charging, frame.accent,
    )
}
