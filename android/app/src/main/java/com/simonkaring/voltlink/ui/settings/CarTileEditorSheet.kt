package com.simonkaring.voltlink.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.data.CarTileLayout
import com.simonkaring.voltlink.ui.theme.Theme

/**
 * Chooses which dials the Android Auto grid shows and in what order. The health tile is
 * always available; metric dials come from the active profile's supported signals.
 */
@Composable
fun CarTileEditorSheet(
    layout: CarTileLayout,
    supportedMetrics: Set<TelemetryMetric>,
    onChange: (CarTileLayout) -> Unit,
    onDismiss: () -> Unit,
) {
    fun update(tiles: List<CarTileKind>) = onChange(CarTileLayout(tiles.take(CarTileLayout.MAX_TILES)))

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.94f)
                .fillMaxHeight(0.86f)
                .clip(RoundedCornerShape(20.dp))
                .background(Theme.backgroundDark)
                .padding(16.dp),
        ) {
            Text(
                stringResource(R.string.car_layout_title),
                color = Theme.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                stringResource(R.string.car_layout_usage, layout.tiles.size, CarTileLayout.MAX_TILES),
                color = Theme.electricCyan,
                fontSize = 12.sp,
            )
            Spacer(Modifier.height(10.dp))

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(layout.tiles) { index, tile ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Theme.cardBackground)
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            tile.title,
                            color = Theme.textPrimary,
                            fontSize = 13.sp,
                            modifier = Modifier.weight(1f),
                        )
                        IconButton(
                            onClick = { update(layout.tiles.toMutableList().also { it.add(index - 1, it.removeAt(index)) }) },
                            enabled = index > 0,
                            modifier = Modifier.size(30.dp),
                        ) {
                            Icon(
                                Icons.Filled.KeyboardArrowUp,
                                contentDescription = stringResource(R.string.action_move_up),
                                tint = if (index > 0) Theme.textSecondary else Theme.trackBackground,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        IconButton(
                            onClick = { update(layout.tiles.toMutableList().also { it.add(index + 1, it.removeAt(index)) }) },
                            enabled = index < layout.tiles.lastIndex,
                            modifier = Modifier.size(30.dp),
                        ) {
                            Icon(
                                Icons.Filled.KeyboardArrowDown,
                                contentDescription = stringResource(R.string.action_move_down),
                                tint = if (index < layout.tiles.lastIndex) Theme.textSecondary else Theme.trackBackground,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        IconButton(
                            onClick = { update(layout.tiles.filterIndexed { i, _ -> i != index }) },
                            modifier = Modifier.size(30.dp),
                        ) {
                            Icon(
                                Icons.Filled.Close,
                                contentDescription = stringResource(R.string.car_layout_remove_row),
                                tint = Theme.textSecondary,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    }
                }

                item {
                    val canAdd = layout.tiles.size < CarTileLayout.MAX_TILES
                    Text(
                        stringResource(R.string.car_layout_add_row),
                        color = Theme.textPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                    if (!canAdd) {
                        Text(
                            stringResource(R.string.car_layout_full),
                            color = Theme.textSecondary,
                            fontSize = 11.sp,
                        )
                    } else {
                        if (layout.tiles.none { it == CarTileKind.Health }) {
                            AddRow(stringResource(R.string.car_row_health)) { update(layout.tiles + CarTileKind.Health) }
                        }
                        supportedMetrics
                            .filter { metric -> layout.tiles.none { it == CarTileKind.Metric(metric) } }
                            .sortedBy { it.displayName }
                            .forEach { metric ->
                                AddRow(metric.displayName) { update(layout.tiles + CarTileKind.Metric(metric)) }
                            }
                    }
                }
            }

            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { onChange(CarTileLayout.default) }) {
                    Text(stringResource(R.string.action_reset), color = Theme.textSecondary, fontSize = 13.sp)
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.action_done), color = Theme.electricCyan, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun AddRow(label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Theme.faintFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = Theme.textPrimary, fontSize = 12.sp, modifier = Modifier.weight(1f))
        Icon(
            Icons.Filled.Add,
            contentDescription = stringResource(R.string.action_add),
            tint = Theme.electricCyan,
            modifier = Modifier.size(16.dp),
        )
        Spacer(Modifier.width(2.dp))
    }
}
