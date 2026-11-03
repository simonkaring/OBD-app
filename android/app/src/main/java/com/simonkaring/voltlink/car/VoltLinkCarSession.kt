package com.simonkaring.voltlink.car

import android.content.Context
import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.Header
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.VoltLinkApplication
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import com.simonkaring.voltlink.data.CarTileKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class VoltLinkCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = VoltLinkCarScreen(carContext)
}

/**
 * Read-only telemetry list: one row per configured tile.
 *
 * The template is invalidated from the shared telemetry flow, so the car screen follows the
 * same connection the phone is using — demo, live or offline.
 */
class VoltLinkCarScreen(carContext: CarContext) : Screen(carContext) {
    private val app: VoltLinkApplication
        get() = carContext.applicationContext as VoltLinkApplication

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    init {
        lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    // Telemetry arrives about once a second; the host throttles template updates.
                    // The scan state is included so the health row still refreshes when a scan
                    // finishes while telemetry is idle or the adapter is offline, and the layout
                    // so rows added in Settings appear without leaving the car screen.
                    scope.launch {
                        combine(
                            app.vehicleData.telemetry,
                            app.vehicleData.connectionState,
                            app.vehicleData.isDemoMode,
                            app.dtcScanner.state,
                            app.vehicleData.settings.carTileLayout,
                        ) { _, _, _, _, _ -> Unit }.collect { invalidate() }
                    }
                }

                override fun onStop(owner: LifecycleOwner) {
                    scope.coroutineContext.cancelChildren()
                }
            },
        )
    }

    override fun onGetTemplate(): Template {
        // The health row reflects the last scan, which the car screen cannot trigger itself.
        val scan = app.dtcScanner.state.value
        return carTelemetryTemplate(
            context = carContext,
            snapshot = app.vehicleData.telemetry.value,
            isDemoMode = app.vehicleData.isDemoMode.value,
            connection = app.vehicleData.connectionState.value,
            tiles = app.vehicleData.settings.carTileLayout.value.tiles,
            storedCodes = scan.lastScanDate?.let { scan.codes.size },
        )
    }
}

/**
 * Builds the car list: one row per configured tile, in the order set in Settings.
 *
 * A [ListTemplate] is scrollable, so the host shows every [com.simonkaring.voltlink.data.CarTileLayout.MAX_TILES]
 * row the layout allows. A [androidx.car.app.model.PaneTemplate] stops at four rows, which silently
 * dropped half of a user's selection.
 */
internal fun carTelemetryTemplate(
    context: Context,
    snapshot: TelemetrySnapshot,
    isDemoMode: Boolean,
    connection: BleConnectionState,
    tiles: List<CarTileKind>,
    storedCodes: Int?,
): ListTemplate {
    val summary = CarTelemetrySummary.of(snapshot = snapshot, isDemoMode = isDemoMode, connection = connection)

    val healthText: (Int?) -> String = { codes ->
        when {
            codes == null -> context.getString(R.string.car_row_not_scanned)
            codes == 0 -> context.getString(R.string.car_row_no_codes)
            else -> context.getString(R.string.car_row_stored_codes, codes)
        }
    }

    val list = ItemList.Builder().apply {
        tiles.forEach { tile ->
            val title = if (tile == CarTileKind.Health) {
                context.getString(R.string.car_row_health)
            } else {
                tile.title
            }
            addItem(
                Row.Builder()
                    .setTitle(title)
                    .addText(carRowValue(tile, summary, snapshot, storedCodes, healthText))
                    .build(),
            )
        }
    }.build()

    return ListTemplate.Builder()
        .setHeader(
            Header.Builder()
                .setTitle(summary.title)
                .setStartHeaderAction(Action.APP_ICON)
                .build(),
        )
        .setSingleList(list)
        .build()
}
