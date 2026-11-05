package com.simonkaring.voltlink.companion

import android.content.Context
import androidx.car.app.model.CarIcon
import androidx.core.graphics.drawable.IconCompat
import com.simonkaring.voltlink.R
import kotlin.math.floor

internal enum class ChargingImageFrame(val lightImage: Int, val darkImage: Int) {
    UNKNOWN(R.drawable.charging_image_unknown_light, R.drawable.charging_image_unknown_dark),
    LEVEL_0(R.drawable.charging_image_level_0_light, R.drawable.charging_image_level_0_dark),
    LEVEL_1(R.drawable.charging_image_level_1_light, R.drawable.charging_image_level_1_dark),
    LEVEL_2(R.drawable.charging_image_level_2_light, R.drawable.charging_image_level_2_dark),
    LEVEL_3(R.drawable.charging_image_level_3_light, R.drawable.charging_image_level_3_dark),
    LEVEL_4(R.drawable.charging_image_level_4_light, R.drawable.charging_image_level_4_dark),
    LEVEL_5(R.drawable.charging_image_level_5_light, R.drawable.charging_image_level_5_dark),
    LEVEL_6(R.drawable.charging_image_level_6_light, R.drawable.charging_image_level_6_dark),
    LEVEL_7(R.drawable.charging_image_level_7_light, R.drawable.charging_image_level_7_dark),
    LEVEL_8(R.drawable.charging_image_level_8_light, R.drawable.charging_image_level_8_dark),
    LEVEL_9(R.drawable.charging_image_level_9_light, R.drawable.charging_image_level_9_dark),
    LEVEL_10(R.drawable.charging_image_level_10_light, R.drawable.charging_image_level_10_dark),
}

/** Coarse visual steps only: 10% SOC or 20 kW, not a vehicle-calibrated charging limit. */
internal object ChargingImageExperiment {
    private val images = mutableMapOf<Pair<ChargingImageFrame, Boolean>, CarIcon>()

    fun socFrame(soc: Double?): ChargingImageFrame =
        level(soc?.takeIf { it <= 100 }, 10.0)

    fun powerFrame(powerKW: Double?): ChargingImageFrame = level(powerKW, 20.0)

    private fun level(value: Double?, step: Double): ChargingImageFrame {
        if (value == null || !value.isFinite() || value < 0) return ChargingImageFrame.UNKNOWN
        return ChargingImageFrame.entries[1 + floor((value / step).coerceAtMost(10.0)).toInt()]
    }

    @Synchronized
    fun icon(context: Context, frame: ChargingImageFrame, darkMode: Boolean): CarIcon =
        images.getOrPut(frame to darkMode) {
            CarIcon.Builder(IconCompat.createWithResource(context, if (darkMode) frame.darkImage else frame.lightImage)).build()
        }

    internal fun render(context: Context, frame: ChargingImageFrame, darkMode: Boolean) =
        renderDial(context, if (frame == ChargingImageFrame.UNKNOWN) null else (frame.ordinal - 1) / 10f, darkMode)
}
