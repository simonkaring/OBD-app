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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.simonkaring.voltlink.R
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
                stringResource(R.string.metric_status_title),
                color = Theme.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                stringResource(R.string.metric_status_subtitle, profileName, metrics.size),
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
                            stringResource(R.string.metric_status_obdb_notice),
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
                                liveMetrics.contains(metric) -> stringResource(R.string.status_live)
                                connected -> stringResource(R.string.status_no_data)
                                else -> stringResource(R.string.status_not_connected)
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
                stringResource(R.string.metric_status_footer),
                color = Theme.textSecondary,
                fontSize = 10.sp,
            )
            Spacer(Modifier.height(4.dp))
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text(stringResource(R.string.action_done), color = Theme.electricCyan, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
