package com.simonkaring.voltlink.car

import android.content.Context
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Header
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Tab
import androidx.car.app.model.TabContents
import androidx.car.app.model.TabTemplate
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.ui.dashboard.metricAvailable
import java.util.Locale

/** Content ids of the two car tabs. */
internal const val CAR_TAB_TELEMETRY = "telemetry"
internal const val CAR_TAB_CHARGING = "charging"

/**
 * Live telemetry tab: the first configured tile as a large dial, the rest as rows beneath it.
 *
 * A [PaneTemplate] is used rather than a grid because the car host draws the pane's picture at
 * full size while grid images shrink to icon size in the dashboard card — a grid of dials left
 * most of the pane empty and the gauges unreadable. One big gauge plus host-rendered rows fills
 * the card and keeps every value crisp at whatever size the host chooses.
 */
internal fun carTelemetryTab(
    context: Context,
    snapshot: TelemetrySnapshot,
    liveMetrics: Set<TelemetryMetric>,
    isDemoMode: Boolean,
    connection: BleConnectionState,
    supportedMetrics: Set<TelemetryMetric>,
    tiles: List<CarTileKind>,
    storedCodes: Int?,
    renderer: CarDialRenderer,
): Template {
    if (tiles.isEmpty()) {
        return MessageTemplate.Builder(context.getString(R.string.car_layout_empty)).build()
    }

    val availability = { metric: TelemetryMetric ->
        metricAvailable(
            metric = metric,
            snapshot = snapshot,
            liveMetrics = liveMetrics,
            isDemoMode = isDemoMode,
            supportedMetrics = supportedMetrics,
            connectionState = connection,
        )
    }

    val pane = Pane.Builder()
    tiles.drop(1).forEach { tile ->
        pane.addRow(row(context, tile, snapshot, storedCodes, availability))
    }

    val hero = tiles.first()
    return PaneTemplate.Builder(heroPane(context, hero, snapshot, storedCodes, availability, renderer, pane))
        .setHeader(Header.Builder().setTitle(heroTitle(context, hero)).build())
        .build()
}

/** The big dial at the top of a tab, or the diagnostics badge when that is the first tile. */
private fun heroPane(
    context: Context,
    hero: CarTileKind,
    snapshot: TelemetrySnapshot,
    storedCodes: Int?,
    availability: (TelemetryMetric) -> Boolean,
    renderer: CarDialRenderer,
    pane: Pane.Builder,
): Pane = when (hero) {
    is CarTileKind.Health -> pane
        .setImage(carIcon(context, R.drawable.ic_car_diagnostics))
        .build()
    is CarTileKind.Metric -> pane
        .setImage(renderer.icon(carDial(hero.metric, snapshot, availability(hero.metric))))
        .build()
}

private fun heroTitle(context: Context, hero: CarTileKind): String = when (hero) {
    is CarTileKind.Health -> context.getString(R.string.car_row_health)
    is CarTileKind.Metric -> hero.metric.displayName
}

/**
 * One secondary metric under the hero dial: the metric name and its value, with the phone's
 * Regen/Draw/Idle chip appended for power.
 */
private fun row(
    context: Context,
    tile: CarTileKind,
    snapshot: TelemetrySnapshot,
    storedCodes: Int?,
    availability: (TelemetryMetric) -> Boolean,
): Row = when (tile) {
    is CarTileKind.Health -> Row.Builder()
        .setTitle(context.getString(R.string.car_row_health))
        .addText(healthText(context, storedCodes))
        .build()
    is CarTileKind.Metric -> {
        val dial = carDial(tile.metric, snapshot, availability(tile.metric))
        val status = powerStatusRes(tile.metric, snapshot)?.let { context.getString(it) }
        Row.Builder()
            .setTitle(tile.metric.displayName)
            .addText(if (status == null) dialText(dial) else "${dialText(dial)} · $status")
            .build()
    }
}

/** "77.6 %" — the dial's centre reading as a plain line of text. */
private fun dialText(dial: CarDial): String =
    dial.unitText?.let { "${dial.valueText} $it" } ?: dial.valueText

private fun healthText(context: Context, storedCodes: Int?): String = when (storedCodes) {
    null -> context.getString(R.string.car_row_not_scanned)
    0 -> context.getString(R.string.car_row_no_codes)
    else -> context.getString(R.string.car_row_stored_codes, storedCodes)
}

/** The phone dial's status chip, which only power shows (Regen, Draw or Idle). */
private fun powerStatusRes(metric: TelemetryMetric, snapshot: TelemetrySnapshot): Int? =
    if (metric != TelemetryMetric.POWER) {
        null
    } else {
        when {
            snapshot.powerKW < -0.5 -> R.string.car_status_regen
            snapshot.powerKW > 5.0 -> R.string.car_status_draw
            else -> R.string.car_status_idle
        }
    }

/**
 * Charging tab: a large state-of-charge dial above the session readouts — charge power, the
 * projected time to the target and the energy this session delivered.
 */
internal fun carChargingTab(
    context: Context,
    snapshot: TelemetrySnapshot,
    liveMetrics: Set<TelemetryMetric>,
    isDemoMode: Boolean,
    connection: BleConnectionState,
    supportedMetrics: Set<TelemetryMetric>,
    charging: CarChargingState,
    renderer: CarDialRenderer,
): PaneTemplate {
    val socAvailable = metricAvailable(
        metric = TelemetryMetric.SOC,
        snapshot = snapshot,
        liveMetrics = liveMetrics,
        isDemoMode = isDemoMode,
        supportedMetrics = supportedMetrics,
        connectionState = connection,
    )
    val powerDial = carChargePowerDial(snapshot.chargePowerKW, charging.isCharging)
    val timeDial = carTimeToTargetDial(
        charging = charging,
        socPct = snapshot.stateOfChargePct,
        reachedText = context.getString(R.string.charging_reached),
    )

    val pane = Pane.Builder()
        .setImage(renderer.icon(carDial(TelemetryMetric.SOC, snapshot, socAvailable)))
        .addRow(
            Row.Builder()
                .setTitle(context.getString(R.string.car_charging_power))
                .addText(
                    "${dialText(powerDial)} · " + context.getString(
                        if (charging.isCharging) R.string.car_charging_status else R.string.car_charging_status_idle,
                    ),
                )
                .build(),
        )
        .addRow(
            Row.Builder()
                .setTitle(context.getString(R.string.car_charging_time_to_target, charging.targetPercent))
                .addText(dialText(timeDial))
                .build(),
        )
        .addRow(
            Row.Builder()
                .setTitle(context.getString(R.string.car_charging_energy))
                .addText(String.format(Locale.US, "%.1f kWh", charging.deliveredKWh))
                .build(),
        )

    return PaneTemplate.Builder(pane.build())
        .setHeader(Header.Builder().setTitle(TelemetryMetric.SOC.displayName).build())
        .build()
}

/**
 * The car screen: a [TabTemplate] holding the telemetry and charging tabs.
 *
 * [activeTabId] must be one of the two content ids; the host calls [onTabSelected] when the user
 * switches tabs, and the screen rebuilds with the newly active content.
 */
internal fun carTabTemplate(
    context: Context,
    activeTabId: String,
    content: Template,
    onTabSelected: (String) -> Unit,
): TabTemplate {
    val tabs = listOf(
        tab(context, R.string.tab_telemetry, CAR_TAB_TELEMETRY, R.drawable.ic_car_telemetry),
        tab(context, R.string.tab_charging, CAR_TAB_CHARGING, R.drawable.ic_car_charging),
    )
    return TabTemplate.Builder(
        object : TabTemplate.TabCallback {
            override fun onTabSelected(contentId: String) = onTabSelected(contentId)
        },
    )
        .setHeaderAction(Action.APP_ICON)
        .addTab(tabs[0])
        .addTab(tabs[1])
        .setTabContents(TabContents.Builder(content).build())
        .setActiveTabContentId(activeTabId)
        .build()
}

private fun tab(context: Context, title: Int, contentId: String, icon: Int): Tab =
    Tab.Builder()
        .setTitle(context.getString(title))
        .setContentId(contentId)
        .setIcon(carIcon(context, icon))
        .build()

/** Monochrome vector icon for tabs and the diagnostics badge. */
private fun carIcon(context: Context, icon: Int): CarIcon =
    CarIcon.Builder(IconCompat.createWithResource(context, icon)).build()
