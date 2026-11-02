package com.simonkaring.voltlink.ui.theme

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background

/** Design tokens ported from `ios/UI/DesignSystem/Theme.swift`. */
object Theme {
    val backgroundDark = Color(0xFF000000)
    val cardBackground = Color(0xFF1C1C1E)

    val electricCyan = Color(0xFF0A84FF)
    val regenGreen = Color(0xFF30D158)
    val highPowerAmber = Color(0xFFFF9F0A)
    val criticalRed = Color(0xFFFF453A)

    val textPrimary = Color.White
    val textSecondary = Color.White.copy(alpha = 0.7f)

    /** Hairline separators over the dark background. */
    val divider = Color.White.copy(alpha = 0.15f)

    /** Legible text/icon color drawn on top of an accent-colored fill. */
    val onAccent = Color.Black

    /** Unfilled track color behind dial/bar gauges. */
    val trackBackground = Color.White.copy(alpha = 0.1f)

    /** Faint chart grid lines drawn over the dark background. */
    val chartGrid = Color.White.copy(alpha = 0.1f)

    /** Slightly stronger fill for interactive chips and secondary buttons. */
    val subtleFill = Color.White.copy(alpha = 0.08f)

    /** Near-invisible fill for unselected cards. */
    val faintFill = Color.White.copy(alpha = 0.04f)

    /** Full-screen dimming layer behind HUD/overlay content. */
    val scrim = Color.Black.copy(alpha = 0.85f)

    val gaugeCyan = Color(0xFF00F0FF)
    private val gaugeBlue = Color(0xFF0073FF)

    val powerGradient = listOf(gaugeCyan, highPowerAmber, criticalRed)
    val regenGradient = listOf(gaugeBlue, regenGreen)
    val speedGradient = listOf(gaugeCyan, gaugeBlue)
    val socGradient = listOf(regenGreen, gaugeCyan)
    val socLowGradient = listOf(highPowerAmber, criticalRed)

    val powerBrush = Brush.horizontalGradient(powerGradient)
    val regenBrush = Brush.horizontalGradient(regenGradient)
    val speedBrush = Brush.horizontalGradient(speedGradient)
    val socBrush = Brush.horizontalGradient(socGradient)
    val socLowBrush = Brush.horizontalGradient(socLowGradient)
}

@Composable
fun VoltLinkTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            background = Theme.backgroundDark,
            surface = Theme.cardBackground,
            onBackground = Theme.textPrimary,
            onSurface = Theme.textPrimary,
            primary = Theme.electricCyan,
            onPrimary = Theme.onAccent,
            secondary = Theme.regenGreen,
            onSecondary = Theme.onAccent,
            error = Theme.criticalRed,
            outline = Theme.divider,
        ),
        content = content,
    )
}

/** Card container matching the iOS `glassCard()` modifier. */
fun Modifier.glassCard(cornerRadius: Dp = 16.dp): Modifier =
    this
        .clip(RoundedCornerShape(cornerRadius))
        .background(Theme.cardBackground)
        .padding(0.dp)
