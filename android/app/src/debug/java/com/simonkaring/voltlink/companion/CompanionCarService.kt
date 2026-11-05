package com.simonkaring.voltlink.companion

import android.content.Context
import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarText
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Tab
import androidx.car.app.model.TabContents
import androidx.car.app.model.TabTemplate
import androidx.car.app.model.Template
import androidx.car.app.annotations.ExperimentalCarApi
import androidx.car.app.validation.HostValidator
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.VoltLinkApplication
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Locale

/** Debug-only IoT experiment. DHU discovery does not establish Play category approval. */
class CompanionCarService : CarAppService() {
    // This service and its permissive DHU validator are never packaged in release.
    override fun createHostValidator(): HostValidator = HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: Intent): Screen = CompanionCarScreen(carContext)
    }
}

internal class CompanionCarScreen(context: CarContext) : Screen(context) {
    private val app = context.applicationContext as VoltLinkApplication
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var observation: Job? = null
    private var state = readState(app)
    private var darkMode = context.isDarkMode
    private var active = "drive"
    private val callback = object : TabTemplate.TabCallback {
        override fun onTabSelected(tabContentId: String) {
            if (tabContentId !in listOf("drive", "charging", "vehicle") || tabContentId == active) return
            active = tabContentId
            invalidate()
        }
    }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                observation?.cancel()
                observation = scope.launch {
                    while (isActive) {
                        val next = readState(app)
                        val nextDarkMode = carContext.isDarkMode
                        if (next != state || nextDarkMode != darkMode) {
                            state = next
                            darkMode = nextDarkMode
                            invalidate()
                        }
                        delay(1_000)
                    }
                }
            }
            override fun onStop(owner: LifecycleOwner) { observation?.cancel() }
            override fun onDestroy(owner: LifecycleOwner) { scope.cancel() }
        })
    }

    override fun onGetTemplate(): Template = companionCarTemplate(
        carContext, state, active, callback, carContext.carAppApiLevel, carContext.isDarkMode,
    )
}

/** Fixed titles/counts: telemetry changes update secondary text, not the template structure. */
internal fun companionCarTemplate(
    context: Context,
    state: CompanionState,
    active: String,
    callback: TabTemplate.TabCallback,
    carAppApiLevel: Int = 7,
    darkMode: Boolean = false,
): TabTemplate {
    fun value(metric: TelemetryMetric) = number(state.metrics[metric], metric.decimalPlaces, metric.unitSymbol)
    fun text(id: Int) = context.getString(id)
    val status = text(when (state.connection) {
        CompanionConnection.DISCONNECTED -> R.string.companion_car_disconnected
        CompanionConnection.CONNECTING -> R.string.companion_connecting
        CompanionConnection.STALE -> R.string.companion_stale
        CompanionConnection.LIVE -> R.string.companion_live
        CompanionConnection.DEMO -> R.string.companion_demo
    })
    val rows = when (active) {
        "vehicle" -> listOf(
            R.string.companion_soc to "${value(TelemetryMetric.SOC)} · $status",
            R.string.companion_car_pack to "${value(TelemetryMetric.PACK_VOLTAGE)} · ${value(TelemetryMetric.BATTERY_TEMP)}",
            R.string.companion_power to value(TelemetryMetric.POWER),
            R.string.companion_car_health to "${value(TelemetryMetric.SOH)} · ${number(state.capacityKWh, 1, "kWh")}",
        )
        else -> emptyList()
    }
    val pane = Pane.Builder()
    rows.forEach { (title, content) -> pane.addRow(Row.Builder().setTitle(text(title)).addText(content).build()) }
    val template = TabTemplate.Builder(callback)
    listOf(
        Triple("drive", R.string.companion_drive, R.drawable.ic_car_telemetry),
        Triple("charging", R.string.companion_charging, R.drawable.ic_car_charging),
        Triple("vehicle", R.string.companion_vehicle, R.drawable.ic_companion_vehicle),
    ).forEach { (id, title, icon) ->
        template.addTab(Tab.Builder().setContentId(id).setTitle(text(title))
            .setIcon(CarIcon.Builder(IconCompat.createWithResource(context, icon)).build()).build())
    }
    return template.setHeaderAction(Action.APP_ICON).setActiveTabContentId(active)
        .setTabContents(TabContents.Builder(
            when (active) {
                "drive", "charging" -> companionGrid(context, state, active == "charging", carAppApiLevel, darkMode)
                else -> PaneTemplate.Builder(pane.build()).build()
            },
        ).build()).build()
}

/** Fixed native tiles with debug-only coarse images; Vehicle keeps its native pane. */
@androidx.annotation.OptIn(ExperimentalCarApi::class)
private fun companionGrid(context: Context, state: CompanionState, charging: Boolean, carAppApiLevel: Int, darkMode: Boolean): GridTemplate {
    val items = ItemList.Builder()
    fun tile(title: Int, value: String, icon: Int, compactValue: String? = null, image: CarIcon? = null) {
        val text = CarText.Builder(value)
        if (compactValue != null) text.addVariant(compactValue)
        items.addItem(GridItem.Builder()
            .setTitle(context.getString(title))
            .setText(text.build())
            .setImage(image ?: CarIcon.Builder(IconCompat.createWithResource(context, icon))
                .setTint(CarColor.DEFAULT).build(), GridItem.IMAGE_TYPE_LARGE)
            .build())
    }
    if (charging) {
        val chargeStatus = context.getString(when (state.charging) {
            CompanionCharging.DISCONNECTED -> R.string.companion_grid_offline
            CompanionCharging.UNAVAILABLE -> R.string.companion_grid_unknown
            CompanionCharging.INACTIVE -> R.string.companion_inactive
            CompanionCharging.ACTIVE -> R.string.companion_grid_charging
            CompanionCharging.COMPLETE -> R.string.companion_grid_charge_complete
        })
        val soc = state.metrics[TelemetryMetric.SOC]
        tile(R.string.companion_soc,
            context.getString(R.string.companion_grid_battery_value, number(soc, 0, "%"), chargeStatus),
            batteryLevelIcon(soc))
        // The first two tiles are the battery and range the Drive grid leads with.
        tile(R.string.companion_grid_range, number(state.rangeKm, 0, "km", state.rangeEstimated), R.drawable.ic_companion_range)
        tile(R.string.companion_grid_charge_power, number(state.chargePowerKW, 1, "kW", state.chargePowerEstimated),
            R.drawable.ic_car_charging,
            image = ChargingImageExperiment.icon(context, ChargingImageExperiment.powerFrame(state.chargePowerKW), darkMode))
        tile(R.string.companion_grid_to80,
            context.getString(R.string.companion_grid_trip_value,
                number(state.secondsTo80?.let { kotlin.math.ceil(it / 60) }, 0, "min", true), gridTripTime(state.chargingSeconds)),
            R.drawable.ic_companion_timer)
        tile(R.string.companion_grid_energy,
            context.getString(R.string.companion_grid_trip_value,
                number(state.energyAddedKWh, 2, "kWh"), number(state.costDKK, 2, "DKK", true)),
            R.drawable.ic_car_charging)
    } else {
        val status = context.getString(when (state.connection) {
            CompanionConnection.DISCONNECTED -> R.string.companion_grid_offline
            CompanionConnection.CONNECTING -> R.string.companion_grid_connecting
            CompanionConnection.STALE -> R.string.companion_grid_stale
            CompanionConnection.LIVE -> R.string.companion_grid_live
            CompanionConnection.DEMO -> R.string.companion_grid_demo
        })
        tile(R.string.companion_soc,
            context.getString(R.string.companion_grid_battery_value, number(state.metrics[TelemetryMetric.SOC], 0, "%"), status),
            batteryLevelIcon(state.metrics[TelemetryMetric.SOC]))
        tile(R.string.companion_grid_range, number(state.rangeKm, 0, "km", state.rangeEstimated), R.drawable.ic_companion_range)
        tile(R.string.companion_speed, number(state.metrics[TelemetryMetric.SPEED], 0, "km/h"), R.drawable.ic_car_telemetry,
            image = SpeedImageExperiment.icon(context, state.metrics[TelemetryMetric.SPEED], darkMode))
        val (powerIcon, powerLabel) = powerIndicator(state)
        val powerValue = number(state.metrics[TelemetryMetric.POWER], 1, "kW")
        tile(R.string.companion_grid_power,
            context.getString(R.string.companion_grid_power_value, powerValue, context.getString(powerLabel)),
            powerIcon, compactValue = powerValue, image = PowerImageExperiment.icon(context, state, darkMode))
        tile(R.string.companion_grid_consumption, number(state.tripConsumption, 1, "").trim(), R.drawable.ic_companion_consumption)
        tile(R.string.companion_grid_trip,
            context.getString(R.string.companion_grid_trip_value, number(state.tripDistanceKm, 1, "km"), gridTripTime(state.tripSeconds)),
            R.drawable.ic_companion_timer)
    }
    val grid = GridTemplate.Builder().setSingleList(items.build())
    // The installed library marks sizing experimental; never send it to API 7 hosts.
    if (carAppApiLevel >= 8) grid.setItemSize(GridTemplate.ITEM_SIZE_LARGE)
    return grid.build()
}

/** Discrete Material battery icons, not a continuously drawn gauge; missing SOC is never empty. */
internal fun batteryLevelIcon(soc: Double?): Int {
    if (soc == null || !soc.isFinite() || soc !in 0.0..100.0) return R.drawable.ic_companion_battery_unknown
    return listOf(
        R.drawable.ic_companion_battery, R.drawable.ic_companion_battery_1,
        R.drawable.ic_companion_battery_2, R.drawable.ic_companion_battery_3,
        R.drawable.ic_companion_battery_4, R.drawable.ic_companion_battery_5,
        R.drawable.ic_companion_battery_6, R.drawable.ic_companion_battery_full,
    )[(soc * 7 / 100).toInt()]
}

internal fun powerIndicator(state: CompanionState): Pair<Int, Int> {
    val power = state.metrics[TelemetryMetric.POWER]?.takeIf { it.isFinite() }
    return when {
        state.charging == CompanionCharging.ACTIVE -> R.drawable.ic_car_charging to R.string.companion_grid_charging
        power == null -> R.drawable.ic_companion_unknown to R.string.companion_grid_unknown
        power < 0 && (state.metrics[TelemetryMetric.SPEED] ?: 0.0) >= 1 ->
            R.drawable.ic_companion_regen to R.string.companion_grid_regen
        power < 0 -> R.drawable.ic_companion_regen to R.string.companion_grid_energy_in
        power > 0 -> R.drawable.ic_companion_draw to R.string.companion_grid_draw
        else -> R.drawable.ic_companion_idle to R.string.companion_grid_idle
    }
}

/** Minutes are sufficient at a glance; the standalone preview retains the second-by-second clock. */
internal fun gridTripTime(seconds: Long?): String = seconds?.coerceAtLeast(0)?.let {
    String.format(Locale.getDefault(), "%d:%02d", it / 3600, it % 3600 / 60)
} ?: "—"
