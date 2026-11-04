package com.simonkaring.voltlink.car

import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.simonkaring.voltlink.VoltLinkApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.launch

/** Minimum gap between template updates; the host re-decodes every dial bitmap per push. */
private const val CAR_REFRESH_MS = 1_000L

class VoltLinkCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = VoltLinkCarScreen(carContext)
}

/**
 * The car dashboard: a tab template with a live telemetry tab and a charging tab, each drawing the
 * phone's pack bar, dials and number cards.
 *
 * Both tabs are built from the same [com.simonkaring.voltlink.services.VehicleDataManager]
 * snapshot and [com.simonkaring.voltlink.services.ChargingTracker] and
 * [com.simonkaring.voltlink.services.TripTracker] state the phone UI reads, so nothing extra is
 * polled while driving, and the templates are invalidated from those flows.
 */
class VoltLinkCarScreen(carContext: CarContext) : Screen(carContext) {
    private val app: VoltLinkApplication
        get() = carContext.applicationContext as VoltLinkApplication

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val dashboards = CarDashboardRenderer()
    private var activeTabId = CAR_TAB_TELEMETRY

    init {
        lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    // The scan state, the car layout, the charging session and the trip are
                    // included so the screen still refreshes when telemetry is idle, a scan
                    // finishes in the background, or a session or trip starts or stops while
                    // the adapter is quiet.
                    val supporting = combine(
                        app.vehicleData.settings.carTileLayout,
                        app.dtcScanner.state,
                        app.chargingTracker.state,
                        app.tripTracker.state,
                    ) { _, _, _, _ -> Unit }
                    scope.launch {
                        combine(
                            app.vehicleData.telemetry,
                            app.vehicleData.connectionState,
                            app.vehicleData.isDemoMode,
                            app.vehicleData.liveMetrics,
                            supporting,
                        ) { _, _, _, _, _ -> Unit }
                            .conflate()
                            .collect {
                                invalidate()
                                delay(CAR_REFRESH_MS)
                            }
                    }
                }

                override fun onStop(owner: LifecycleOwner) {
                    scope.coroutineContext.cancelChildren()
                }
            },
        )
    }

    override fun onGetTemplate(): Template {
        val manager = app.vehicleData
        val snapshot = manager.telemetry.value
        val isDemoMode = manager.isDemoMode.value
        val connection = manager.connectionState.value
        val supportedMetrics = manager.selectedProfile.supportedMetrics
        val liveMetrics = manager.liveMetrics.value
        val scan = app.dtcScanner.state.value
        val charging = app.chargingTracker.state.value
        val trip = app.tripTracker.state.value

        val content = if (activeTabId == CAR_TAB_CHARGING) {
            carChargingTab(
                context = carContext,
                snapshot = snapshot,
                liveMetrics = liveMetrics,
                isDemoMode = isDemoMode,
                connection = connection,
                supportedMetrics = supportedMetrics,
                charging = CarChargingState(
                    isCharging = charging.isCharging,
                    targetPercent = charging.targetPercent.toInt(),
                    secondsToTarget = charging.secondsToTarget,
                    deliveredKWh = charging.current?.totalKWhDelivered ?: 0.0,
                    peakPowerKW = charging.current?.peakPowerKW ?: 0.0,
                    sessionStartSocPct = charging.current?.startSocPct,
                ),
                renderer = dashboards,
            )
        } else {
            carTelemetryTab(
                context = carContext,
                snapshot = snapshot,
                liveMetrics = liveMetrics,
                isDemoMode = isDemoMode,
                connection = connection,
                supportedMetrics = supportedMetrics,
                tiles = manager.settings.carTileLayout.value.tiles,
                storedCodes = scan.lastScanDate?.let { scan.codes.size },
                trip = CarTripState(
                    isRecording = trip.isRecording,
                    distanceKm = trip.current?.distanceKm ?: 0.0,
                    durationSeconds = trip.current?.duration?.seconds ?: 0,
                    autoTrips = trip.isAutoTripEnabled,
                ),
                renderer = dashboards,
            )
        }

        return carTabTemplate(
            context = carContext,
            activeTabId = activeTabId,
            content = content,
        ) { contentId ->
            if (contentId != activeTabId) {
                activeTabId = contentId
                invalidate()
            }
        }
    }
}
