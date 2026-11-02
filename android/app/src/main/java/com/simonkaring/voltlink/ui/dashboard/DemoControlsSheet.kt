package com.simonkaring.voltlink.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.demo.DemoScenario
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme

/** Demo/Simulation control sheet: scenarios plus manual speed, throttle and regen overrides. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DemoControlsSheet(manager: VehicleDataManager, onDismiss: () -> Unit) {
    val simulation = manager.simulation
    var scenario by remember { mutableStateOf(simulation.scenario) }
    var speedOverride by remember { mutableStateOf(simulation.userSpeedOverride?.toFloat()) }
    var throttleOverride by remember { mutableStateOf(simulation.userThrottleOverride?.toFloat()) }
    var regenOverride by remember { mutableStateOf(simulation.userRegenOverride?.toFloat()) }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Theme.cardBackground) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                stringResource(R.string.demo_title),
                color = Theme.textPrimary,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                stringResource(R.string.demo_hint),
                color = Theme.textSecondary,
                fontSize = 13.sp,
            )

            DemoScenario.entries.forEach { entry ->
                val selected = scenario == entry
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (selected) Theme.electricCyan.copy(alpha = 0.18f) else Theme.subtleFill)
                        .clickable {
                            scenario = entry
                            simulation.scenario = entry
                        }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                ) {
                    Text(
                        text = entry.label,
                        color = if (selected) Theme.electricCyan else Theme.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                }
            }

            SliderRow(
                label = stringResource(R.string.demo_manual_speed),
                value = speedOverride,
                range = 0f..140f,
                suffix = "km/h",
                onChange = {
                    speedOverride = it
                    simulation.userSpeedOverride = it.toDouble()
                },
            )
            SliderRow(
                label = stringResource(R.string.demo_throttle),
                value = throttleOverride,
                range = 0f..1f,
                suffix = "%",
                scale = 100f,
                onChange = {
                    throttleOverride = it
                    simulation.userThrottleOverride = it.toDouble()
                },
            )
            SliderRow(
                label = stringResource(R.string.demo_regen),
                value = regenOverride,
                range = 0f..1f,
                suffix = "%",
                scale = 100f,
                onChange = {
                    regenOverride = it
                    simulation.userRegenOverride = it.toDouble()
                },
            )

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(
                    onClick = {
                        manager.setDemoMode(true)
                        simulation.start()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = Theme.electricCyan),
                ) {
                    Text(stringResource(R.string.demo_mode), color = Theme.onAccent, fontWeight = FontWeight.SemiBold)
                }
                OutlinedButton(onClick = { manager.setDemoMode(false) }) {
                    Text(stringResource(R.string.demo_live), color = Theme.textPrimary)
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = {
                    speedOverride = null
                    throttleOverride = null
                    regenOverride = null
                    simulation.userSpeedOverride = null
                    simulation.userThrottleOverride = null
                    simulation.userRegenOverride = null
                }) {
                    Text(stringResource(R.string.action_reset), color = Theme.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun SliderRow(
    label: String,
    value: Float?,
    range: ClosedFloatingPointRange<Float>,
    suffix: String,
    scale: Float = 1f,
    onChange: (Float) -> Unit,
) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = Theme.textPrimary, fontSize = 14.sp, modifier = Modifier.weight(1f))
            Text(
                text = value?.let { String.format(java.util.Locale.US, "%.0f %s", it * scale, suffix) }
                    ?: stringResource(R.string.demo_auto),
                color = Theme.textSecondary,
                fontSize = 13.sp,
            )
        }
        Slider(
            value = value ?: range.start,
            onValueChange = onChange,
            valueRange = range,
        )
    }
}
