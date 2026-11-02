package com.simonkaring.voltlink.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.ui.theme.Theme

/**
 * Which metrics the active profile claims to support, and whether each one is arriving from
 * the car right now — the Android equivalent of the iOS profile metric status screen.
 */
@Composable
fun ProfileMetricStatusSheet(
    profileName: String,
    supportedMetrics: Set<TelemetryMetric>,
    liveMetrics: Set<TelemetryMetric>,
    isConnected: Boolean,
    isDemoMode: Boolean,
    isCommunityObdbProfile: Boolean,
    onDismiss: () -> Unit,
) {
    val metrics = TelemetryMetric.entries.filter { it in supportedMetrics }
    val connected = isConnected || isDemoMode

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .fillMaxHeight(0.88f)
                .clip(RoundedCornerShape(20.dp))
                .background(Theme.backgroundDark)
                .padding(16.dp),
        ) {
            Text(
                "Profile metric status",
                color = Theme.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "$profileName — ${metrics.size} metrics",
                color = Theme.electricCyan,
                fontSize = 12.sp,
            )
            Spacer(Modifier.height(10.dp))

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                if (isCommunityObdbProfile) {
                    item {
                        Text(
                            "OBDb community profile: experimental definitions. Compare readings " +
                                "with your car. Charging assumes negative pack current means " +
                                "charging and needs fresh stationary wheel speed. Coolant " +
                                "temperature is not battery-cell temperature. Adapted from " +
                                "OBDb/Mercedes-Benz-EQA under CC BY-SA 4.0.",
                            color = Theme.highPowerAmber,
                            fontSize = 11.sp,
                            modifier = Modifier.padding(bottom = 8.dp),
                        )
                    }
                }
                items(metrics) { metric ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            metric.displayName,
                            color = Theme.textPrimary,
                            fontSize = 13.sp,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = when {
                                liveMetrics.contains(metric) -> "Live"
                                connected -> "No data"
                                else -> "Not connected"
                            },
                            color = when {
                                liveMetrics.contains(metric) -> Theme.regenGreen
                                connected -> Theme.highPowerAmber
                                else -> Theme.textSecondary
                            },
                            fontSize = 11.sp,
                            fontWeight = if (liveMetrics.contains(metric)) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
            }

            Text(
                "\"Live\" means this metric arrived in the most recent poll cycle. A metric " +
                    "drops back to \"No data\" after repeated failed polls for its command.",
                color = Theme.textSecondary,
                fontSize = 10.sp,
            )
            Spacer(Modifier.height(4.dp))
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text("Done", color = Theme.electricCyan, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
