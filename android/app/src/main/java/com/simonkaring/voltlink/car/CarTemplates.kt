package com.simonkaring.voltlink.car

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.text.SpannableString
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.ForegroundCarColorSpan
import androidx.car.app.model.Header
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Tab
import androidx.car.app.model.TabContents
import androidx.car.app.model.TabTemplate
import androidx.car.app.model.Template
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import com.simonkaring.voltlink.ui.components.formatMetric
import com.simonkaring.voltlink.ui.dashboard.metricAvailable
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt

/** Content ids of the two car tabs. */
internal const val CAR_TAB_TELEMETRY = "telemetry"
internal const val CAR_TAB_CHARGING = "charging"

/** A pane template silently drops rows past the fourth, so the tabs never build more. */
private const val MAX_PANE_ROWS = 4

/**
 * Live telemetry tab: the phone's live dashboard in the pane picture — the pack bar over the
 * speed and power dials — beside rows for whether a trip is being recorded, the number cards
 * (trip average and the like) and diagnostics, in the order the layout lists them.
 *
 * A [PaneTemplate] is used rather than a grid because the car host draws a grid's images at icon
 * size, and a pane's picture slot is a fixed square, so [CarDashboardRenderer] draws the bar and
 * dials as one square image. The rows stay host-rendered so the numbers and status text are crisp
 * at whatever size the host chooses.
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
    trip: CarTripState,
    renderer: CarDashboardRenderer,
): Template {
    if (tiles.isEmpty()) {
        return MessageTemplate.Builder(context.getString(R.string.car_layout_empty)).build()
    }

    val available = { metric: TelemetryMetric ->
        metricAvailable(
            metric = metric,
            snapshot = snapshot,
            liveMetrics = liveMetrics,
            isDemoMode = isDemoMode,
            supportedMetrics = supportedMetrics,
            connectionState = connection,
        )
    }

    val metrics = tiles.filterIsInstance<CarTileKind.Metric>().map { it.metric }
    val dashboard = CarDashboard(
        bar = TelemetryMetric.SOC.takeIf { it in metrics }?.let {
            carSocBar(
                label = context.getString(R.string.gauges_hv_battery),
                trailing = batteryTempLabel(context, snapshot, available(TelemetryMetric.BATTERY_TEMP)),
                socPct = if (available(TelemetryMetric.SOC)) snapshot.stateOfChargePct else null,
                isCharging = snapshot.isCharging,
            )
        },
        dials = metrics.filter { it in DIAL_METRICS }.map { dialCard(context, it, snapshot, available(it)) },
    )

    val rows = listOf(tripRow(context, trip)) + tiles.mapNotNull { tile ->
        when (tile) {
            CarTileKind.Health -> healthRow(context, storedCodes)
            is CarTileKind.Metric -> tile.metric
                .takeIf { it != TelemetryMetric.SOC && it !in DIAL_METRICS }
                ?.let { numberRow(context, it, snapshot, available(it)) }
        }
    }

    val pane = Pane.Builder()
    if (!dashboard.isEmpty) pane.setImage(renderer.icon(dashboard))
    rows.take(MAX_PANE_ROWS).forEach { pane.addRow(it) }

    return PaneTemplate.Builder(pane.build())
        .setHeader(Header.Builder().setTitle(context.getString(R.string.tab_telemetry)).build())
        .build()
}

/** The metrics the phone dashboard shows as dials by default; every other metric is a number row. */
private val DIAL_METRICS = setOf(TelemetryMetric.SPEED, TelemetryMetric.POWER)

/** The phone dial, with its Regen/Draw/Idle chip for power and the metric name for the rest. */
private fun dialCard(
    context: Context,
    metric: TelemetryMetric,
    snapshot: TelemetrySnapshot,
    available: Boolean,
): CarDial = carDial(metric, snapshot, available).copy(
    status = (if (available) powerStatusRes(metric, snapshot) else null)
        ?.let { context.getString(it) } ?: metric.displayName,
)

/** The phone's number card as a row: the metric's name over its value and unit, `--` when unavailable. */
private fun numberRow(
    context: Context,
    metric: TelemetryMetric,
    snapshot: TelemetrySnapshot,
    available: Boolean,
): Row = statusRow(
    context = context,
    icon = R.drawable.ic_car_telemetry,
    tint = if (available) CarColor.BLUE else CarColor.DEFAULT,
    title = if (metric == TelemetryMetric.TRIP_AVERAGE_CONSUMPTION) {
        context.getString(R.string.car_label_trip_average)
    } else {
        metric.displayName
    },
    text = "${formatMetric(metric.value(snapshot), metric, isUnavailable = !available)} ${metric.unitSymbol}",
)

/** "HV: 24.0 °C" beside the pack bar, like the phone's header, once the temperature is live. */
private fun batteryTempLabel(context: Context, snapshot: TelemetrySnapshot, available: Boolean): String? =
    if (available) {
        context.getString(
            R.string.gauges_hv_prefix,
            String.format(Locale.US, "%.1f %s", snapshot.batteryTempC, TelemetryMetric.BATTERY_TEMP.unitSymbol),
        )
    } else {
        null
    }

/** Whether a trip is being logged: green with its distance and time while recording. */
private fun tripRow(context: Context, trip: CarTripState): Row =
    if (trip.isRecording) {
        statusRow(
            context = context,
            icon = R.drawable.ic_car_trip,
            tint = CarColor.GREEN,
            title = context.getString(R.string.car_trip_recording),
            text = green(
                String.format(Locale.US, "%.1f km · ", trip.distanceKm) +
                    carDurationText(trip.durationSeconds.toDouble()),
            ),
        )
    } else {
        statusRow(
            context = context,
            icon = R.drawable.ic_car_trip,
            tint = CarColor.DEFAULT,
            title = context.getString(R.string.car_trip_idle),
            text = context.getString(
                if (trip.autoTrips) R.string.car_trip_idle_auto else R.string.car_trip_idle_manual,
            ),
        )
    }

private fun healthRow(context: Context, storedCodes: Int?): Row = statusRow(
    context = context,
    icon = R.drawable.ic_car_diagnostics,
    tint = when (storedCodes) {
        null -> CarColor.DEFAULT
        0 -> CarColor.GREEN
        else -> CarColor.YELLOW
    },
    title = context.getString(R.string.car_row_health),
    text = healthText(context, storedCodes),
)

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
 * Charging tab: the pack bar with the charge target marked over the charge power and
 * time-to-target dials, beside rows that say whether a session is running and give its energy and
 * peak power.
 */
internal fun carChargingTab(
    context: Context,
    snapshot: TelemetrySnapshot,
    liveMetrics: Set<TelemetryMetric>,
    isDemoMode: Boolean,
    connection: BleConnectionState,
    supportedMetrics: Set<TelemetryMetric>,
    charging: CarChargingState,
    renderer: CarDashboardRenderer,
): PaneTemplate {
    val available = { metric: TelemetryMetric ->
        metricAvailable(
            metric = metric,
            snapshot = snapshot,
            liveMetrics = liveMetrics,
            isDemoMode = isDemoMode,
            supportedMetrics = supportedMetrics,
            connectionState = connection,
        )
    }
    val socAvailable = available(TelemetryMetric.SOC)

    val dashboard = CarDashboard(
        bar = carSocBar(
            label = context.getString(R.string.gauges_hv_battery),
            trailing = batteryTempLabel(context, snapshot, available(TelemetryMetric.BATTERY_TEMP)),
            socPct = if (socAvailable) snapshot.stateOfChargePct else null,
            isCharging = charging.isCharging,
            marks = listOf(charging.targetPercent / 100.0),
        ),
        dials = listOf(
            carChargePowerDial(snapshot.chargePowerKW, charging.isCharging).copy(
                status = context.getString(
                    if (charging.isCharging) R.string.car_charging_power else R.string.car_charging_status_idle,
                ),
            ),
            carTimeToTargetDial(
                charging = charging,
                socPct = snapshot.stateOfChargePct,
                reachedText = context.getString(R.string.charging_reached),
            ).copy(status = context.getString(R.string.car_charging_time_to_target, charging.targetPercent)),
        ),
    )

    val session = if (charging.isCharging) {
        val soc = snapshot.stateOfChargePct.roundToInt()
        statusRow(
            context = context,
            icon = R.drawable.ic_car_charging,
            tint = CarColor.GREEN,
            title = context.getString(R.string.car_charging_status),
            text = green(
                charging.sessionStartSocPct
                    ?.let { context.getString(R.string.car_charging_session, it.roundToInt(), soc) }
                    ?: "$soc%",
            ),
        )
    } else {
        statusRow(
            context = context,
            icon = R.drawable.ic_car_charging,
            tint = CarColor.DEFAULT,
            title = context.getString(R.string.car_charging_status_idle),
            text = context.getString(R.string.car_charging_plug_in),
        )
    }

    val pane = Pane.Builder()
        .setImage(renderer.icon(dashboard))
        .addRow(session)
        .addRow(
            statusRow(
                context = context,
                icon = R.drawable.ic_car_charging,
                tint = CarColor.BLUE,
                title = context.getString(R.string.car_charging_energy),
                text = String.format(Locale.US, "%.1f kWh", charging.deliveredKWh),
            ),
        )
        .addRow(
            statusRow(
                context = context,
                icon = R.drawable.ic_car_telemetry,
                tint = CarColor.BLUE,
                title = context.getString(R.string.car_charging_peak),
                text = String.format(Locale.US, "%.1f %s", charging.peakPowerKW, TelemetryMetric.POWER.unitSymbol),
            ),
        )
    return PaneTemplate.Builder(pane.build())
        .setHeader(Header.Builder().setTitle(context.getString(R.string.tab_charging)).build())
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

/** A row with a host-tinted glyph, a title and one line of detail: how the tabs report state. */
private fun statusRow(context: Context, icon: Int, tint: CarColor, title: String, text: CharSequence): Row =
    Row.Builder()
        .setImage(CarIcon.Builder(rasterIcon(context, icon)).setTint(tint).build(), Row.IMAGE_TYPE_ICON)
        .setTitle(title)
        .addText(text)
        .build()

private val rasterIcons = ConcurrentHashMap<Int, IconCompat>()

/**
 * A row glyph as pixels rather than a resource id: the host caches resource icons by id, so a
 * drawable added after Android Auto first saw the app can show a stale or blank glyph until the
 * host restarts. The tab icons stay resource-based; their ids have not moved.
 */
private fun rasterIcon(context: Context, icon: Int): IconCompat = rasterIcons.getOrPut(icon) {
    val bitmap = Bitmap.createBitmap(ROW_ICON_PX, ROW_ICON_PX, Bitmap.Config.ARGB_8888)
    checkNotNull(ContextCompat.getDrawable(context, icon)).apply {
        setBounds(0, 0, ROW_ICON_PX, ROW_ICON_PX)
        draw(Canvas(bitmap))
    }
    IconCompat.createWithBitmap(bitmap)
}

private const val ROW_ICON_PX = 96

private fun green(text: String): CharSequence = SpannableString(text).apply {
    setSpan(ForegroundCarColorSpan.create(CarColor.GREEN), 0, length, 0)
}

/** Monochrome vector icon for tabs; the host applies its own tint. */
private fun carIcon(context: Context, icon: Int): CarIcon =
    CarIcon.Builder(IconCompat.createWithResource(context, icon)).build()
