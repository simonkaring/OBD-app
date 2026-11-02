package com.simonkaring.voltlink.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.UnitPrefs
import com.simonkaring.voltlink.ui.theme.Theme
import java.util.Locale

/**
 * Mirrored windshield HUD: large speed, power and SoC on a black background, flipped on both
 * axes so it reads correctly when reflected in the glass. Tap anywhere to exit.
 */
@Composable
fun HudScreen(manager: VehicleDataManager, units: UnitPrefs, onExit: () -> Unit) {
    val snapshot by manager.telemetry.collectAsStateWithLifecycle()
    val liveMetrics by manager.liveMetrics.collectAsStateWithLifecycle()
    val isDemoMode by manager.isDemoMode.collectAsStateWithLifecycle()
    val showSoc = isDemoMode || TelemetryMetric.SOC in liveMetrics
    val showPower = isDemoMode || TelemetryMetric.POWER in liveMetrics

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Theme.backgroundDark)
            .clickable(onClick = onExit)
            .graphicsLayer {
                rotationY = 180f
                rotationX = 180f
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.fillMaxWidth().padding(24.dp),
        ) {
            Text(
                text = if (isDemoMode) "DEMO" else "VOLTLINK",
                color = Theme.textSecondary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 4.sp,
            )
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text(
                    text = String.format(Locale.US, "%.0f", units.value(TelemetryMetric.SPEED, snapshot)),
                    color = Theme.textPrimary,
                    fontSize = 130.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    text = units.unit(TelemetryMetric.SPEED),
                    color = Theme.textSecondary,
                    fontSize = 24.sp,
                    modifier = Modifier.padding(bottom = 26.dp, start = 6.dp),
                )
            }
            if (showPower) {
                Text(
                    text = String.format(
                        Locale.US,
                        "%+.1f %s",
                        units.value(TelemetryMetric.POWER, snapshot),
                        units.unit(TelemetryMetric.POWER),
                    ),
                    color = if (snapshot.powerKW < 0) Theme.regenGreen else Theme.gaugeCyan,
                    fontSize = 34.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            if (showSoc) {
                Spacer(Modifier.height(10.dp))
                Text(
                    text = String.format(Locale.US, "%.0f%%", snapshot.stateOfChargePct),
                    color = if (snapshot.isCharging) Theme.regenGreen else Theme.textPrimary,
                    fontSize = 46.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.height(28.dp))
            Text("Tap to exit", color = Theme.textSecondary, fontSize = 13.sp)
        }
    }
}
