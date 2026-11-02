package com.simonkaring.voltlink.ui.settings

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.vehicles.Powertrain
import com.simonkaring.voltlink.core.vehicles.VehicleBrand
import com.simonkaring.voltlink.core.vehicles.VehicleCatalog
import com.simonkaring.voltlink.core.vehicles.VehicleModelEntry
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * Searchable catalog picker (the iOS `VehicleCatalogView` equivalent). The 599-row dataset is
 * parsed off the main thread the first time the dialog opens; picking a row selects the profile
 * it maps to and remembers its name for trips, the widget and reminders.
 */
@Composable
fun VehicleCatalogPicker(manager: VehicleDataManager, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val brands by produceState<List<VehicleBrand>?>(initialValue = null) {
        value = withContext(Dispatchers.Default) { VehicleCatalog.load(context) }
    }
    val selectedModelId by manager.settings.selectedModelId.collectAsState()
    var query by remember { mutableStateOf("") }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Theme.backgroundDark)
                .padding(horizontal = 14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(
                    stringResource(R.string.catalog_title),
                    color = Theme.textPrimary,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f).padding(vertical = 14.dp),
                )
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.action_close), color = Theme.electricCyan)
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(Theme.subtleFill)
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Search, contentDescription = null, tint = Theme.textSecondary)
                Box(Modifier.weight(1f).padding(start = 8.dp)) {
                    if (query.isEmpty()) {
                        Text(stringResource(R.string.catalog_search), color = Theme.textSecondary, fontSize = 14.sp)
                    }
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it },
                        singleLine = true,
                        textStyle = TextStyle(color = Theme.textPrimary, fontSize = 14.sp),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (query.isNotEmpty()) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = stringResource(R.string.catalog_clear_search),
                        tint = Theme.textSecondary,
                        modifier = Modifier.clickable { query = "" },
                    )
                }
            }

            Spacer(Modifier.height(10.dp))
            Text(
                manager.vehicleDisplayName,
                color = Theme.textSecondary,
                fontSize = 12.sp,
            )

            if (brands == null) {
                Text(
                    stringResource(R.string.catalog_loading),
                    color = Theme.textSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(vertical = 20.dp),
                )
                return@Column
            }

            val normalized = query.trim().lowercase(Locale.US)
            val rows = if (normalized.isEmpty()) {
                brands!!.flatMap { brand -> brand.models.map { brand to it } }
            } else {
                brands!!
                    .flatMap { brand -> brand.models.map { brand to it } }
                    .filter { (brand, model) ->
                        brand.name.lowercase(Locale.US).contains(normalized) ||
                            model.modelName.lowercase(Locale.US).contains(normalized) ||
                            model.years.contains(normalized)
                    }
            }

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(6.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                if (rows.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.catalog_empty),
                            color = Theme.textSecondary,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(vertical = 16.dp),
                        )
                    }
                }
                items(rows, key = { (_, model) -> model.id }) { (brand, model) ->
                    CatalogRow(
                        brandName = brand.name,
                        model = model,
                        selected = model.id == selectedModelId,
                        showBrand = normalized.isNotEmpty(),
                        onClick = {
                            manager.selectVehicle(model)
                            onDismiss()
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun CatalogRow(
    brandName: String,
    model: VehicleModelEntry,
    selected: Boolean,
    showBrand: Boolean,
    onClick: () -> Unit,
) {
    val accent = if (selected) Theme.electricCyan else Theme.textPrimary
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) Theme.electricCyan.copy(alpha = 0.14f) else Theme.faintFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(model.modelName, color = accent, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                if (showBrand) {
                    Text(brandName, color = Theme.textSecondary, fontSize = 11.sp)
                }
            }
            Text(
                stringResource(powertrainBadge(model)),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
        Spacer(Modifier.height(3.dp))
        Text(
            buildString {
                append(model.years)
                if (model.batteryCapacityKWh > 0) {
                    append(String.format(Locale.US, " · %.1f kWh", model.batteryCapacityKWh))
                }
                model.estimatedRangeKm?.let { append(String.format(Locale.US, " · %.0f km", it)) }
            },
            color = Theme.textSecondary,
            fontSize = 11.sp,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            if (model.hasDedicatedProfile) {
                "${model.profileId.displayName} · ${model.telemetrySupport.label}"
            } else {
                stringResource(R.string.catalog_generic)
            },
            color = if (model.hasDedicatedProfile) Theme.regenGreen else Theme.textSecondary,
            fontSize = 10.sp,
        )
    }
}

private fun powertrainBadge(model: VehicleModelEntry): Int =
    when (model.powertrain) {
        Powertrain.EV -> R.string.catalog_powertrain_ev
        Powertrain.PHEV -> R.string.catalog_powertrain_phev
        Powertrain.ICE -> R.string.catalog_powertrain_ice
    }
