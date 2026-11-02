package com.simonkaring.voltlink

import android.Manifest
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import com.simonkaring.voltlink.core.demo.DemoScenario
import com.simonkaring.voltlink.core.obd.BleConnectionState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Demo mode lifecycle: switching it off and back on has to bring polling back, and simulated
 * driving or charging must never be written to the history database.
 */
@RunWith(AndroidJUnit4::class)
class DemoModeLifecycleTest {
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.POST_NOTIFICATIONS,
    )

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<MainActivity>()

    private val app get() = rule.activity.application as VoltLinkApplication

    /** The application outlives the activity: leave the simulation off and on its default cycle. */
    @After
    fun restoreDemoState() {
        app.vehicleData.setDemoMode(false)
        app.vehicleData.simulation.scenario = DemoScenario.CITY_DRIVING
    }

    @Test
    fun demoSwitchedOffAndOnResumesPolling() {
        val data = app.vehicleData
        // The application outlives an activity, so an earlier test may have left demo on.
        data.setDemoMode(false)
        assertFalse(data.isDemoMode.value)
        assertFalse(data.connectionState.value.isConnected)

        data.setDemoMode(true)
        awaitUntil { data.connectionState.value == BleConnectionState.DemoMode }
        awaitUntil { data.liveMetrics.value.isNotEmpty() }

        data.setDemoMode(false)
        assertEquals(BleConnectionState.Disconnected, data.connectionState.value)
        assertTrue("stale metrics survived leaving demo", data.liveMetrics.value.isEmpty())

        // The regression: the mock adapter stayed Disconnected, so polling never resumed.
        data.setDemoMode(true)
        awaitUntil { data.liveMetrics.value.isNotEmpty() }
        assertEquals(BleConnectionState.DemoMode, data.connectionState.value)
    }

    @Test
    fun demoRecordingsStayOutOfTheHistoryDatabase() {
        val data = app.vehicleData
        data.setDemoMode(false)
        data.setDemoMode(true)
        awaitUntil { data.liveMetrics.value.isNotEmpty() }

        val tripsBefore = app.historyStore.trips.value.size
        val sessionsBefore = app.historyStore.chargingSessions.value.size

        app.tripTracker.start(data.telemetry.value.stateOfChargePct, "Demo")
        awaitUntil { app.tripTracker.state.value.isRecording }
        app.tripTracker.stop(data.telemetry.value.stateOfChargePct)
        awaitUntil { !app.tripTracker.state.value.isRecording }
        // A persisted trip would land in the database within this window.
        Thread.sleep(SETTLE_MILLIS)
        assertEquals("a demo trip reached the history database", tripsBefore, app.historyStore.trips.value.size)

        // A demo DC charge is closed when the source changes; it must not be saved either.
        data.simulation.scenario = DemoScenario.DC_FAST_CHARGING
        awaitUntil(timeoutMillis = 20_000) { app.chargingTracker.state.value.isCharging }
        data.setDemoMode(false)
        awaitUntil { app.chargingTracker.state.value.current == null }
        Thread.sleep(SETTLE_MILLIS)
        assertEquals(
            "a demo charging session reached the history database",
            sessionsBefore,
            app.historyStore.chargingSessions.value.size,
        )
    }

    /** Polls a plain condition from the test thread; the admin flows settle off the UI thread. */
    private fun awaitUntil(timeoutMillis: Long = 10_000, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return
            Thread.sleep(50)
        }
        fail("condition was not met within ${timeoutMillis}ms")
    }

    private companion object {
        const val SETTLE_MILLIS = 500L
    }
}
