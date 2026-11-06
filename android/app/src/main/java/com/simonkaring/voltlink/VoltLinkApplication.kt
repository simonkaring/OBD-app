package com.simonkaring.voltlink

import android.app.Application
import com.simonkaring.voltlink.core.shortcuts.AppShortcuts
import com.simonkaring.voltlink.core.vehicles.ServiceReminderMonitor
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import com.simonkaring.voltlink.core.widget.TelemetryWidgetStore
import com.simonkaring.voltlink.data.DtcLocalDatabase
import com.simonkaring.voltlink.data.HistoryStore
import com.simonkaring.voltlink.data.PreferencesServiceReminderStore
import com.simonkaring.voltlink.services.ChargingTracker
import com.simonkaring.voltlink.services.DtcScannerService
import com.simonkaring.voltlink.services.TripTracker
import com.simonkaring.voltlink.services.VehicleDataManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/** Composition root: one long-lived scope owns the adapter, poller, trackers and scanner. */
class VoltLinkApplication : Application() {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    lateinit var vehicleData: VehicleDataManager
        private set
    lateinit var dtcScanner: DtcScannerService
        private set
    lateinit var historyStore: HistoryStore
        private set
    lateinit var tripTracker: TripTracker
        private set
    lateinit var chargingTracker: ChargingTracker
        private set
    lateinit var notifications: com.simonkaring.voltlink.core.notifications.NotificationService
        private set
    lateinit var serviceReminder: ServiceReminderMonitor
        private set

    /** Demo state the trackers were last told about; they never persist simulated rows. */
    private var trackersDemoMode = false
    private var chargingStatusShown = false
    private var chargingActive = false
    private var targetNotified = false
    private var lastSessionId: String? = null
    private var lastScanDate: java.time.Instant? = null

    /** Last stored battery-health reading, so a 1 Hz SOH does not rewrite the database. */
    private var lastBatteryHealthSoh: Double? = null
    private var lastBatteryHealthAt: Instant? = null

    override fun onCreate() {
        super.onCreate()
        // ABRP definitions ship as assets; install the reader before any profile is built.
        com.simonkaring.voltlink.core.vehicles.AbrpProfileLoader.install(this)
        notifications = com.simonkaring.voltlink.core.notifications.NotificationService(this)
        serviceReminder = ServiceReminderMonitor(PreferencesServiceReminderStore(this))
        vehicleData = VehicleDataManager(this, appScope)
        dtcScanner = DtcScannerService(appScope, vehicleData, DtcLocalDatabase(this))
        historyStore = HistoryStore(this, appScope)
        tripTracker = TripTracker(appScope, historyStore)
        chargingTracker = ChargingTracker(appScope, historyStore) {
            com.simonkaring.voltlink.services.lastKnownLocation(this@VoltLinkApplication)
        }
        observeTelemetry()
        observeChargingState()
        observeDiagnostics()
        observeAdapterLoss()
        observeTripShortcuts()
        observeServiceInterval()
        observeTripLocation()
    }

    /**
     * Starts and stops the foreground GPS recorder with the trip recorder. The service itself
     * refuses to start without location permission, which is only requested from Start Trip.
     */
    private fun observeTripLocation() {
        appScope.launch {
            tripTracker.state
                .map { it.isRecording }
                .distinctUntilChanged()
                .collect { recording ->
                    if (recording) {
                        com.simonkaring.voltlink.services.TripLocationService.start(this@VoltLinkApplication)
                    } else {
                        com.simonkaring.voltlink.services.TripLocationService.stop(this@VoltLinkApplication)
                    }
                }
        }
    }

    /** The launcher shortcut's label follows the trip recorder state. */
    private fun observeTripShortcuts() {
        appScope.launch {
            tripTracker.state
                .map { it.isRecording }
                .distinctUntilChanged()
                .collect { recording -> AppShortcuts.publish(this@VoltLinkApplication, recording) }
        }
    }

    private fun observeChargingState() {
        val chargingFeed = combine(
            chargingTracker.state,
            vehicleData.telemetry,
            vehicleData.settings.chargeTargetPercent,
        ) { tracker, snapshot, target -> Triple(tracker, snapshot, target) }
        val alertPreferences = combine(
            vehicleData.settings.chargingStatusEnabled,
            vehicleData.settings.alertChargeTargetReached,
            vehicleData.settings.alertChargingFinished,
        ) { status, target, finished -> Triple(status, target, finished) }

        appScope.launch {
            combine(chargingFeed, alertPreferences) { feed, alerts -> feed to alerts }
                .collect { (feed, alerts) ->
                    val (tracker, snapshot, target) = feed
                    val (statusEnabled, targetEnabled, finishedEnabled) = alerts

                    if (statusEnabled && tracker.isCharging) {
                        notifications.showChargingStatus(
                            socPct = snapshot.stateOfChargePct,
                            powerKW = snapshot.chargePowerKW,
                            targetPct = target,
                            secondsToTarget = tracker.secondsToTarget,
                        )
                        chargingStatusShown = true
                    } else if (chargingStatusShown) {
                        notifications.cancelChargingStatus()
                        chargingStatusShown = false
                    }

                    if (tracker.isCharging) {
                        chargingActive = true
                        if (targetEnabled && !targetNotified && snapshot.stateOfChargePct >= target) {
                            targetNotified = true
                            notifications.notifyChargeTargetReached(target, snapshot.stateOfChargePct)
                        }
                    } else if (chargingActive) {
                        chargingActive = false
                        targetNotified = false
                        if (finishedEnabled) {
                            historyStore.chargingSessions.value.firstOrNull()?.let { session ->
                                if (session.id != lastSessionId && session.endTime != null) {
                                    lastSessionId = session.id
                                    notifications.notifyChargingFinished(
                                        session.startSocPct,
                                        session.endSocPct,
                                        session.totalKWhDelivered,
                                    )
                                }
                            }
                        }
                    }
                }
        }
    }

    /**
     * Keeps the last vehicle-reported service distance and raises the weekly reminder. Only
     * measured values count — the simulator has no service interval.
     */
    private fun observeServiceInterval() {
        appScope.launch {
            vehicleData.selectedProfileId.collect {
                // The tracker caches the pack size for its time-to-target estimate, so a profile
                // switch has to move it too; it used to be read once at startup.
                chargingTracker.updateCapacity(vehicleData.selectedProfile.batteryUsableCapacityKWh)
                serviceReminder.refresh(vehicleData.vehicleDisplayName)
            }
        }
    }

    private fun observeDiagnostics() {
        appScope.launch {
            combine(dtcScanner.state, vehicleData.settings.alertFaultCodes) { state, enabled -> state to enabled }
                .collect { (state, enabled) ->
                    if (!enabled || state.isScanning || state.lastScanDate == null) return@collect
                    if (state.lastScanDate != lastScanDate) {
                        lastScanDate = state.lastScanDate
                        notifications.notifyFaultCodes(state.codes.size)
                    }
                }
        }
    }

    private fun observeAdapterLoss() {
        appScope.launch {
            vehicleData.connectionState.collect { state ->
                if (state is com.simonkaring.voltlink.core.obd.BleConnectionState.Error &&
                    vehicleData.settings.alertAdapterDisconnected.value
                ) {
                    notifications.notifyAdapterLost(tripTracker.state.value.isRecording)
                }
            }
        }
    }

    private fun observeTelemetry() {
        appScope.launch {
            combine(
                vehicleData.telemetry,
                vehicleData.liveMetrics,
                vehicleData.isDemoMode,
                vehicleData.settings.chargeTargetPercent,
            ) { snapshot, liveMetrics, isDemoMode, target ->
                TelemetryFeed(snapshot, liveMetrics, isDemoMode, target)
            }.collect { feed ->
                // The widget cannot observe flows, so every snapshot is mirrored to prefs.
                TelemetryWidgetStore.publish(
                    context = this@VoltLinkApplication,
                    snapshot = feed.snapshot,
                    vehicleName = vehicleData.vehicleDisplayName,
                    isConnected = vehicleData.connectionState.value.isConnected,
                    isCharging = chargingTracker.state.value.isCharging,
                    isDemoMode = feed.isDemoMode,
                )
                // Demo recordings never reach the history database; tell the trackers about the
                // source change before they see its first snapshot. That snapshot still belongs
                // to the previous source, so it is not fed to them at all.
                if (feed.isDemoMode != trackersDemoMode) {
                    trackersDemoMode = feed.isDemoMode
                    tripTracker.setDemoMode(feed.isDemoMode)
                    chargingTracker.setDemoMode(feed.isDemoMode)
                } else {
                    val hasPower = feed.isDemoMode || TelemetryMetric.POWER in feed.liveMetrics
                    tripTracker.process(feed.snapshot, vehicleData.vehicleDisplayName, hasPowerData = hasPower)
                    chargingTracker.onTelemetry(feed.snapshot, feed.targetPercent.toDouble())
                }
                // Battery health is a measured SOH reading, never a simulated one. SOH arrives on
                // every poll, so a reading is stored only when it moved or an hour has passed.
                if (!feed.isDemoMode && TelemetryMetric.SOH in feed.liveMetrics &&
                    shouldRecordBatteryHealth(feed.snapshot.stateOfHealthPct)
                ) {
                    lastBatteryHealthSoh = feed.snapshot.stateOfHealthPct
                    lastBatteryHealthAt = Instant.now()
                    historyStore.recordBatteryHealth(
                        sohPct = feed.snapshot.stateOfHealthPct,
                        vehicleName = vehicleData.vehicleDisplayName,
                    )
                }
                if (!feed.isDemoMode) {
                    val serviceKm = feed.snapshot.communityValues?.get(TelemetryMetric.SERVICE_DISTANCE)
                    if (serviceKm != null) {
                        val outcome = serviceReminder.observe(
                            distanceKm = serviceKm,
                            vehicleName = vehicleData.vehicleDisplayName,
                            enabled = vehicleData.settings.serviceRemindersEnabled.value,
                        )
                        if (outcome?.reminderDue == true) notifications.notifyServiceDue(serviceKm)
                    }
                }
            }
        }
        chargingTracker.updateCapacity(vehicleData.selectedProfile.batteryUsableCapacityKWh)
    }

    /** True when the reading is worth a database round trip: a new value, or an hour later. */
    private fun shouldRecordBatteryHealth(sohPct: Double): Boolean {
        val previousSoh = lastBatteryHealthSoh ?: return true
        val previousAt = lastBatteryHealthAt ?: return true
        if (Duration.between(previousAt, Instant.now()).toHours() >= 1) return true
        return kotlin.math.abs(sohPct - previousSoh) >= 0.5
    }

    private data class TelemetryFeed(
        val snapshot: com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot,
        val liveMetrics: Set<TelemetryMetric>,
        val isDemoMode: Boolean,
        val targetPercent: Int,
    )
}
