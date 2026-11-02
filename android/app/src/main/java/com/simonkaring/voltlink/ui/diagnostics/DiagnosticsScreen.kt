package com.simonkaring.voltlink.ui.diagnostics

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.obd.DtcCode
import com.simonkaring.voltlink.core.obd.DtcSeverity
import com.simonkaring.voltlink.core.obd.FreezeFrameSignal
import com.simonkaring.voltlink.services.DtcScannerService
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** ECU fault-code scanner with severity detail, freeze frames and Mode 04 clearing. */
@Composable
fun DiagnosticsScreen(
    manager: VehicleDataManager,
    scanner: DtcScannerService,
    modifier: Modifier = Modifier,
) {
    val state by scanner.state.collectAsStateWithLifecycle()
    val isDemoMode by manager.isDemoMode.collectAsStateWithLifecycle()
    val isConnected by manager.connectionState.collectAsStateWithLifecycle()
    val expanded = remember { mutableStateMapOf<String, Boolean>() }

    LazyColumn(
        modifier = modifier.fillMaxSize().padding(horizontal = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp, top = 8.dp),
    ) {
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(Theme.cardBackground)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(stringResource(R.string.dx_health), color = Theme.textSecondary, fontSize = 12.sp)
                Text(
                    text = state.healthSummary,
                    color = when {
                        state.isScanning -> Theme.electricCyan
                        state.errorMessage != null -> Theme.highPowerAmber
                        state.codes.isEmpty() && state.scanSucceeded -> Theme.regenGreen
                        state.codes.isNotEmpty() -> Theme.criticalRed
                        else -> Theme.textPrimary
                    },
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                if (state.lastScanDate != null) {
                    Text(
                        text = stringResource(
                            R.string.dx_last_scan,
                            DateTimeFormatter.ofPattern("d MMM HH:mm")
                                .withZone(ZoneId.systemDefault())
                                .format(state.lastScanDate),
                        ),
                        color = Theme.textSecondary,
                        fontSize = 12.sp,
                    )
                }
                if (state.isScanning) {
                    Spacer(Modifier.height(4.dp))
                    LinearProgressIndicator(
                        progress = { state.progress.toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                        color = Theme.electricCyan,
                        trackColor = Theme.trackBackground,
                    )
                }
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Button(
                        onClick = { scanner.scan() },
                        enabled = !state.isScanning && (isDemoMode || isConnected.isConnected),
                        colors = ButtonDefaults.buttonColors(containerColor = Theme.electricCyan),
                    ) {
                        if (state.isScanning) {
                            CircularProgressIndicator(modifier = Modifier.height(16.dp).width(16.dp), strokeWidth = 2.dp, color = Theme.onAccent)
                            Spacer(Modifier.width(8.dp))
                        }
                        Text(
                            if (state.isScanning) stringResource(R.string.dx_scanning) else stringResource(R.string.dx_scan),
                            color = Theme.onAccent,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    OutlinedButton(
                        onClick = { scanner.clearCodes() },
                        enabled = !state.isScanning && state.codes.isNotEmpty(),
                    ) {
                        Text(stringResource(R.string.dx_clear), color = Theme.textPrimary)
                    }
                }
                if (isDemoMode) {
                    Text(
                        stringResource(R.string.dx_demo_hint),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                    )
                }
            }
        }

        if (state.codes.isEmpty() && state.scanSucceeded) {
            item {
                Text(
                    stringResource(R.string.dx_none),
                    color = Theme.textSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            }
        }

        items(state.codes, key = { it.code }) { code ->
            DtcCard(code = code, expanded = expanded[code.code] == true) {
                expanded[code.code] = !(expanded[code.code] ?: false)
            }
        }
    }
}

@Composable
private fun DtcCard(code: DtcCode, expanded: Boolean, onToggle: () -> Unit) {
    val severityColor = when (code.severity) {
        DtcSeverity.CRITICAL -> Theme.criticalRed
        DtcSeverity.WARNING -> Theme.highPowerAmber
        DtcSeverity.ADVISORY -> Theme.electricCyan
        DtcSeverity.UNKNOWN -> Theme.textSecondary
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Theme.cardBackground)
            .clickable(onClick = onToggle)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(code.code, color = Theme.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(8.dp))
            Text(
                text = code.severity.label,
                color = severityColor,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .background(severityColor.copy(alpha = 0.18f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
            Spacer(Modifier.weight(1f))
            Text(code.category, color = Theme.textSecondary, fontSize = 11.sp)
        }
        Text(code.title, color = Theme.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        Text(code.description, color = Theme.textSecondary, fontSize = 13.sp, maxLines = if (expanded) 20 else 2)

        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val frames = code.freezeFrameData
                if (frames != null && frames.isNotEmpty()) {
                    Section(stringResource(R.string.dx_conditions)) {
                        FreezeFrameSignal.orderedValues(frames).forEach { (label, value) ->
                            Row(Modifier.fillMaxWidth()) {
                                Text(label, color = Theme.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                                Text(value, color = Theme.textPrimary, fontSize = 12.sp)
                            }
                        }
                    }
                }
                if (code.symptoms.isNotEmpty()) {
                    Section(stringResource(R.string.dx_symptoms)) {
                        code.symptoms.forEach { Text("• $it", color = Theme.textSecondary, fontSize = 12.sp) }
                    }
                }
                if (code.possibleFixes.isNotEmpty()) {
                    Section(stringResource(R.string.dx_fixes)) {
                        code.possibleFixes.forEach { Text("• $it", color = Theme.textSecondary, fontSize = 12.sp) }
                    }
                }
                if (code.definitionSource != null) {
                    Text(code.definitionSource, color = Theme.textSecondary, fontSize = 10.sp)
                }
            }
        }
        if (!expanded) {
            Text(stringResource(R.string.dx_tap_hint), color = Theme.textSecondary, fontSize = 10.sp)
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, color = Theme.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        content()
    }
}
