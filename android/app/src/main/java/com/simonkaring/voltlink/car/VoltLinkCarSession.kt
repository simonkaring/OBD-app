package com.simonkaring.voltlink.car

import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.VoltLinkApplication
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
 * Read-only telemetry pane: state of charge, power, speed and range.
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
                    scope.launch {
                        combine(
                            app.vehicleData.telemetry,
                            app.vehicleData.connectionState,
                            app.vehicleData.isDemoMode,
                        ) { _, _, _ -> Unit }.collect { invalidate() }
                    }
                }

                override fun onStop(owner: LifecycleOwner) {
                    scope.coroutineContext.cancelChildren()
                }
            },
        )
    }

    override fun onGetTemplate(): Template {
        val snapshot = app.vehicleData.telemetry.value
        val summary = CarTelemetrySummary.of(
            snapshot = snapshot,
            isDemoMode = app.vehicleData.isDemoMode.value,
            connection = app.vehicleData.connectionState.value,
        )
        // The health row reflects the last scan, which the pane cannot trigger itself.
        val scan = app.dtcScanner.state.value
        val storedCodes = scan.lastScanDate?.let { scan.codes.size }

        val healthText: (Int?) -> String = { codes ->
            when {
                codes == null -> carContext.getString(R.string.car_row_not_scanned)
                codes == 0 -> carContext.getString(R.string.car_row_no_codes)
                else -> carContext.getString(R.string.car_row_stored_codes, codes)
            }
        }

        val pane = Pane.Builder().apply {
            app.vehicleData.settings.carTileLayout.value.tiles.forEach { tile ->
                val title = if (tile == CarTileKind.Health) {
                    carContext.getString(R.string.car_row_health)
                } else {
                    tile.title
                }
                addRow(row(title, carRowValue(tile, summary, snapshot, storedCodes, healthText)))
            }
        }.build()

        return PaneTemplate.Builder(pane)
            .setTitle(summary.title)
            .build()
    }

    private fun row(title: String, value: String): Row =
        Row.Builder()
            .setTitle(title)
            .addText(value)
            .build()
}
