package com.simonkaring.voltlink.core.demo

import com.simonkaring.voltlink.core.obd.BleConnectionState
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The demo drive follows the toggle: it starts when demo is switched on, never with the object. */
class MockObdAdapterTest {
    @Test
    fun demoDriveStartsAndStopsWithTheToggle() = runTest {
        val adapter = MockObdAdapter(this)
        assertFalse("a freshly built adapter must not be driving", adapter.state.value.isConnected)

        adapter.startSimulation()
        assertEquals(BleConnectionState.DemoMode, adapter.state.value)
        assertTrue(adapter.state.value.isConnected)

        adapter.disconnect()
        assertEquals(BleConnectionState.Disconnected, adapter.state.value)

        // Switching demo back on has to reconnect, otherwise the polling loop never resumes.
        adapter.startSimulation()
        assertEquals(BleConnectionState.DemoMode, adapter.state.value)

        adapter.stopSimulation()
    }
}
