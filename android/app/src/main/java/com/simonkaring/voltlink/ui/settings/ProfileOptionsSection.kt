package com.simonkaring.voltlink.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.vehicles.VehicleCatalog
import com.simonkaring.voltlink.core.vehicles.VehicleModelEntry
import com.simonkaring.voltlink.core.vehicles.VehicleProfileId
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One selectable decoder for the selected car, with the metrics it can actually read. */
private data class ProfileOption(
    val profileId: VehicleProfileId,
    val label: String,
    val supportLabel: String,
    val metrics: List<String>,
    /** Catalog row to apply, or null for a decoder swap that has no row of its own. */
    val model: VehicleModelEntry?,
)

private fun metricsOf(id: VehicleProfileId): List<String> =
    id.makeProfile().supportedMetrics
        .sortedBy { it.displayName }
        .map { metric -> "${metric.displayName} (${metric.unitSymbol})" }

/**
 * The alternative decoders for the selected car: same-family catalog rows (the EQA's verified and
 * OBDb entries) plus the community ABRP tables that decode a car the catalog binds elsewhere
 * (MEB, E-GMP). A car with a single decoder renders nothing.
 *
 * A catalog row is a profile binding, so choosing one goes through `selectVehicle`, which keeps the
 * catalog selection, the profile and the re-initialisation in step. A decoder without a row swaps
 * through `selectProfile(keepVehicle = true)` instead, leaving the picked car and its name alone.
 */
@Composable
fun ProfileOptionsSection(
    manager: VehicleDataManager,
    selectedModelId: String?,
    currentProfileId: VehicleProfileId,
) {
    val context = LocalContext.current
    val options by produceState(
        initialValue = emptyList<ProfileOption>(),
        selectedModelId,
        currentProfileId,
    ) {
        value = withContext(Dispatchers.Default) {
            val models = VehicleCatalog.load(context).flatMap { it.models }
            val rows = VehicleCatalog.profileOptions(models, selectedModelId, currentProfileId)
                .map { model ->
                    ProfileOption(
                        profileId = model.profileId,
                        label = model.resolvedVariantDisplayName,
                        supportLabel = model.telemetrySupport.label,
                        metrics = metricsOf(model.profileId),
                        model = model,
                    )
                }
            val alternatives = VehicleCatalog.profileAlternatives(currentProfileId).map { id ->
                ProfileOption(
                    profileId = id,
                    label = id.displayName,
                    supportLabel = id.supportLabel,
                    metrics = metricsOf(id),
                    model = null,
                )
            }
            // Keep the active decoder visible even when it has no catalog row; otherwise a swap
            // would leave one option and hide the section that made the swap possible.
            val current = ProfileOption(
                profileId = currentProfileId,
                label = currentProfileId.displayName,
                supportLabel = currentProfileId.supportLabel,
                metrics = metricsOf(currentProfileId),
                model = null,
            )
            (rows + alternatives + current).distinctBy { it.profileId }
        }
    }
    if (options.size < 2) return
    var expanded by remember { mutableStateOf<VehicleProfileId?>(null) }

    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            stringResource(R.string.settings_profile_options),
            color = Theme.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            stringResource(R.string.settings_profile_options_hint),
            color = Theme.textSecondary,
            fontSize = 11.sp,
        )
        options.forEach { option ->
            val profileId = option.profileId
            val selected = profileId == currentProfileId
            val isExpanded = expanded == profileId
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (selected) Theme.electricCyan.copy(alpha = 0.14f) else Theme.faintFill)
                    .clickable {
                        val row = option.model
                        if (row != null) {
                            manager.selectVehicle(row)
                        } else {
                            manager.selectProfile(option.profileId, keepVehicle = true)
                        }
                    }
                    .padding(horizontal = 10.dp, vertical = 8.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            option.label,
                            color = if (selected) Theme.electricCyan else Theme.textPrimary,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                        )
                        val count = option.metrics.size
                        Text(
                            "${option.supportLabel} · " +
                                pluralStringResource(R.plurals.settings_published_metrics, count, count),
                            color = Theme.textSecondary,
                            fontSize = 11.sp,
                        )
                    }
                    if (selected) {
                        Icon(
                            Icons.Filled.Check,
                            contentDescription = null,
                            tint = Theme.electricCyan,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                    IconButton(
                        onClick = { expanded = if (isExpanded) null else profileId },
                        modifier = Modifier.size(30.dp),
                    ) {
                        Icon(
                            if (isExpanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown,
                            contentDescription = stringResource(
                                if (isExpanded) R.string.settings_hide_metrics else R.string.settings_show_metrics,
                            ),
                            tint = Theme.textSecondary,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                if (isExpanded) {
                    Text(
                        option.metrics.joinToString(", "),
                        color = Theme.textSecondary,
                        fontSize = 11.sp,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }
    }
}
