package com.simonkaring.voltlink.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.vehicles.Powertrain
import com.simonkaring.voltlink.core.vehicles.VehicleBrand
import com.simonkaring.voltlink.core.vehicles.VehicleCatalog
import com.simonkaring.voltlink.core.vehicles.VehicleModelEntry
import com.simonkaring.voltlink.core.vehicles.VehicleModelFamily
import com.simonkaring.voltlink.services.VehicleDataManager
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * Searchable catalog picker (the iOS `VehicleProfilePickerSheet` equivalent). The 599-row dataset
 * is parsed off the main thread the first time the dialog opens and browsed in the same
 * brand -> model family -> model year -> variant order as iOS; a search at the brand level
 * flattens the tree and matches brand, family, model, variant and model year in one list.
 */
@Composable
fun VehicleCatalogPicker(manager: VehicleDataManager, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val brands by produceState<List<VehicleBrand>?>(initialValue = null) {
        value = withContext(Dispatchers.Default) { VehicleCatalog.load(context) }
    }
    val selectedModelId by manager.settings.selectedModelId.collectAsState()

    var query by remember { mutableStateOf("") }
    var evOnly by remember { mutableStateOf(true) }
    var level by remember { mutableStateOf(CatalogLevel.BRANDS) }
    var brandId by remember { mutableStateOf<String?>(null) }
    var familyId by remember { mutableStateOf<String?>(null) }
    var modelYear by remember { mutableStateOf<Int?>(null) }

    // EV-only by default: the dataset is dominated by petrol rows that all fall back to the
    // generic decoder, and they only make the list longer.
    val visibleBrands = remember(brands, evOnly) {
        brands.orEmpty()
            .mapNotNull { brand ->
                val models = if (evOnly) brand.models.filter { it.powertrain == Powertrain.EV } else brand.models
                if (models.isEmpty()) null else VehicleBrand(brand.id, brand.name, models)
            }
            .sortedBy { it.name.lowercase(Locale.US) }
    }
    val brand = visibleBrands.firstOrNull { it.id == brandId }
    val families = remember(brand) { brand?.modelFamilies.orEmpty().sortedBy { it.name.lowercase(Locale.US) } }
    val family = families.firstOrNull { it.id == familyId }
    val normalizedQuery = query.trim()

    fun choose(model: VehicleModelEntry) {
        manager.selectVehicle(model)
        onDismiss()
    }

    fun goBack() {
        when (level) {
            CatalogLevel.VARIANTS -> {
                modelYear = null
                // Families with a single variant skipped the year list on the way in.
                level = if ((family?.variants?.size ?: 0) > 1) CatalogLevel.YEARS else CatalogLevel.MODELS
            }
            CatalogLevel.YEARS -> {
                familyId = null
                level = CatalogLevel.MODELS
            }
            CatalogLevel.MODELS -> {
                brandId = null
                query = ""
                level = CatalogLevel.BRANDS
            }
            CatalogLevel.BRANDS -> onDismiss()
        }
    }
    BackHandler(enabled = level != CatalogLevel.BRANDS) { goBack() }

    val title = when (level) {
        CatalogLevel.BRANDS -> stringResource(R.string.catalog_title)
        CatalogLevel.MODELS -> brand?.name ?: stringResource(R.string.catalog_title)
        CatalogLevel.YEARS -> stringResource(R.string.catalog_model_year)
        CatalogLevel.VARIANTS -> buildString {
            append(family?.name.orEmpty())
            modelYear?.let { append(" · $it") }
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Theme.backgroundDark)
                .padding(horizontal = 14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                if (level != CatalogLevel.BRANDS) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = stringResource(R.string.catalog_back),
                        tint = Theme.electricCyan,
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .clickable { goBack() }
                            .padding(6.dp)
                            .size(20.dp),
                    )
                    Spacer(Modifier.size(10.dp))
                }
                Text(
                    title,
                    color = Theme.textPrimary,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(vertical = 14.dp),
                )
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.action_close), color = Theme.electricCyan)
                }
            }

            // Searching only makes sense while picking a brand or a model family; the year and
            // variant levels are short lists already.
            if (level == CatalogLevel.BRANDS || level == CatalogLevel.MODELS) {
                SearchField(
                    query = query,
                    placeholder = if (level == CatalogLevel.BRANDS) {
                        stringResource(R.string.catalog_search)
                    } else {
                        stringResource(R.string.catalog_search_models, brand?.name.orEmpty())
                    },
                    onQueryChange = { query = it },
                )
                Spacer(Modifier.height(10.dp))
            }

            if (level == CatalogLevel.BRANDS) {
                SegmentedRow(
                    options = listOf(
                        "ev" to stringResource(R.string.catalog_filter_ev),
                        "all" to stringResource(R.string.catalog_filter_all),
                    ),
                    selected = if (evOnly) "ev" else "all",
                    onSelect = { evOnly = it == "ev" },
                )
                Spacer(Modifier.height(10.dp))
            }

            Text(
                stringResource(R.string.catalog_current_vehicle, manager.vehicleDisplayName),
                color = Theme.textSecondary,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(8.dp))

            if (brands == null) {
                Text(
                    stringResource(R.string.catalog_loading),
                    color = Theme.textSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(vertical = 20.dp),
                )
                return@Column
            }

            when (level) {
                CatalogLevel.BRANDS -> BrandLevel(
                    brands = visibleBrands,
                    query = normalizedQuery,
                    selectedModelId = selectedModelId,
                    onOpenBrand = { picked ->
                        brandId = picked.id
                        query = ""
                        level = CatalogLevel.MODELS
                    },
                    onChoose = ::choose,
                )
                CatalogLevel.MODELS -> FamilyLevel(
                    families = families.filter { family ->
                        normalizedQuery.isEmpty() ||
                            family.name.contains(normalizedQuery, ignoreCase = true) ||
                            family.variants.any { it.matchesCatalogQuery(normalizedQuery) }
                    },
                    onOpenFamily = { picked ->
                        familyId = picked.id
                        query = ""
                        modelYear = null
                        // One variant means there is nothing to narrow down by year.
                        level = if (picked.variants.size > 1) CatalogLevel.YEARS else CatalogLevel.VARIANTS
                    },
                )
                CatalogLevel.YEARS -> YearLevel(
                    family = family,
                    selectedModelId = selectedModelId,
                    onOpenYear = { picked ->
                        modelYear = picked
                        level = CatalogLevel.VARIANTS
                    },
                )
                CatalogLevel.VARIANTS -> VariantLevel(
                    variants = family?.let { if (modelYear == null) it.variants else it.variantsFor(modelYear!!) }
                        .orEmpty()
                        .sortedBy { it.resolvedVariantDisplayName.lowercase(Locale.US) },
                    selectedModelId = selectedModelId,
                    onChoose = ::choose,
                )
            }
        }
    }
}

private enum class CatalogLevel { BRANDS, MODELS, YEARS, VARIANTS }

/** Brand list, or a flat list of matching vehicles once a search is typed. */
@Composable
private fun BrandLevel(
    brands: List<VehicleBrand>,
    query: String,
    selectedModelId: String?,
    onOpenBrand: (VehicleBrand) -> Unit,
    onChoose: (VehicleModelEntry) -> Unit,
) {
    val matches = remember(brands, query) {
        if (query.isEmpty()) {
            emptyList()
        } else {
            brands.flatMap { brand -> brand.models.map { brand to it } }
                .filter { (_, model) -> model.matchesCatalogQuery(query) }
        }
    }
    CatalogList(count = if (query.isEmpty()) brands.size else matches.size) {
        if (query.isEmpty()) {
            items(brands, key = { it.id }) { brand ->
                val families = brand.modelFamilies
                CatalogNavRow(
                    title = brand.name,
                    subtitle = pluralStringResource(R.plurals.catalog_models_count, families.size, families.size),
                    onClick = { onOpenBrand(brand) },
                )
            }
        } else {
            items(matches, key = { (_, model) -> model.id }) { (brand, model) ->
                CatalogRow(
                    brandName = brand.name,
                    model = model,
                    selected = model.id == selectedModelId,
                    showBrand = true,
                    onClick = { onChoose(model) },
                )
            }
        }
    }
}

@Composable
private fun FamilyLevel(families: List<VehicleModelFamily>, onOpenFamily: (VehicleModelFamily) -> Unit) {
    CatalogList(count = families.size) {
        items(families, key = { it.id }) { family ->
            CatalogNavRow(
                title = family.name,
                subtitle = pluralStringResource(
                    R.plurals.catalog_variants_count,
                    family.variants.size,
                    family.variants.size,
                ),
                onClick = { onOpenFamily(family) },
            )
        }
    }
}

@Composable
private fun YearLevel(
    family: VehicleModelFamily?,
    selectedModelId: String?,
    onOpenYear: (Int?) -> Unit,
) {
    val years = family?.modelYears.orEmpty()
    // The year is not persisted on its own; derive it from the selected row so the checkmark
    // still points at the right entry.
    val selectedYears = family?.variants?.firstOrNull { it.id == selectedModelId }?.modelYears().orEmpty()
    CatalogList(count = years.size + 1) {
        items(years, key = { it }) { year ->
            CatalogNavRow(
                title = year.toString(),
                subtitle = pluralStringResource(
                    R.plurals.catalog_variants_count,
                    family?.variantsFor(year)?.size ?: 0,
                    family?.variantsFor(year)?.size ?: 0,
                ),
                onClick = { onOpenYear(year) },
                trailing = if (year in selectedYears) {
                    { Icon(Icons.Filled.Check, contentDescription = null, tint = Theme.electricCyan, modifier = Modifier.size(18.dp)) }
                } else {
                    null
                },
            )
        }
        item {
            CatalogNavRow(
                title = stringResource(R.string.catalog_year_unspecified),
                subtitle = stringResource(R.string.catalog_year_unspecified_hint),
                onClick = { onOpenYear(null) },
            )
        }
    }
}

@Composable
private fun VariantLevel(variants: List<VehicleModelEntry>, selectedModelId: String?, onChoose: (VehicleModelEntry) -> Unit) {
    CatalogList(count = variants.size) {
        items(variants, key = { it.id }) { model ->
            CatalogRow(
                brandName = model.modelFamilyName.orEmpty(),
                model = model,
                selected = model.id == selectedModelId,
                showBrand = false,
                onClick = { onChoose(model) },
            )
        }
    }
}

/** Shared list body: the scrollable column plus the empty / no-match message. */
@Composable
private fun CatalogList(count: Int, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        if (count == 0) {
            item {
                Text(
                    stringResource(R.string.catalog_empty),
                    color = Theme.textSecondary,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(vertical = 16.dp),
                )
            }
        }
        content()
    }
}

@Composable
private fun SearchField(query: String, placeholder: String, onQueryChange: (String) -> Unit) {
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
                Text(placeholder, color = Theme.textSecondary, fontSize = 14.sp)
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
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
                modifier = Modifier.clickable { onQueryChange("") },
            )
        }
    }
}

/** A drill-down row: brand, model family or model year, with a chevron unless it shows a check. */
@Composable
private fun CatalogNavRow(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Theme.faintFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                title,
                color = Theme.textPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                subtitle,
                color = Theme.textSecondary,
                fontSize = 11.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (trailing != null) {
            trailing()
        } else {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = Theme.textSecondary,
                modifier = Modifier.size(18.dp),
            )
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
                Text(
                    model.resolvedVariantDisplayName,
                    color = accent,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (showBrand) {
                    Text(brandName, color = Theme.textSecondary, fontSize = 11.sp, maxLines = 1)
                }
            }
            if (selected) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = Theme.electricCyan, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(6.dp))
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
