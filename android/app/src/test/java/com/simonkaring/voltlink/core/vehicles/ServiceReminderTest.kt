package com.simonkaring.voltlink.core.vehicles

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServiceReminderTest {
    private class InMemoryStore : ServiceReminderStore {
        val doubles = mutableMapOf<String, Double>()
        val longs = mutableMapOf<String, Long>()

        override fun getDouble(key: String): Double? = doubles[key]
        override fun putDouble(key: String, value: Double) {
            doubles[key] = value
        }

        override fun getLong(key: String): Long? = longs[key]
        override fun putLong(key: String, value: Long) {
            longs[key] = value
        }
    }

    private val now = 1_700_000_000_000L

    @Test
    fun `stores and reads a snapshot per vehicle`() {
        val monitor = ServiceReminderMonitor(InMemoryStore())
        assertNull(monitor.snapshot("EQA"))

        monitor.observe(distanceKm = 4_200.0, vehicleName = "EQA", enabled = true, atMillis = now)
        assertEquals(4_200.0, monitor.snapshot("EQA")!!.remainingKm, 0.001)
        assertEquals(now, monitor.snapshot("EQA")!!.observedAtMillis)
        assertNull(monitor.snapshot("ID.4"))

        monitor.observe(distanceKm = 900.0, vehicleName = "ID.4", enabled = true, atMillis = now)
        assertEquals(4_200.0, monitor.snapshot("EQA")!!.remainingKm, 0.001)
        assertEquals(900.0, monitor.snapshot("ID.4")!!.remainingKm, 0.001)
    }

    @Test
    fun `rejects implausible readings and blank vehicle names`() {
        val monitor = ServiceReminderMonitor(InMemoryStore())
        assertNull(monitor.observe(Double.NaN, "EQA", enabled = true))
        assertNull(monitor.observe(-5.0, "EQA", enabled = true))
        assertNull(monitor.observe(200_000.0, "EQA", enabled = true))
        assertNull(monitor.observe(1_000.0, "", enabled = true))
        assertNull(monitor.snapshot("EQA"))
    }

    @Test
    fun `reminds only below the threshold and only when enabled`() {
        assertTrue(ServiceReminderMonitor.shouldRemind(800.0, 1_000.0, null, enabled = true, atMillis = now))
        assertFalse(ServiceReminderMonitor.shouldRemind(1_200.0, 1_000.0, null, enabled = true, atMillis = now))
        assertFalse(ServiceReminderMonitor.shouldRemind(800.0, 1_000.0, null, enabled = false, atMillis = now))
    }

    @Test
    fun `cooldown suppresses repeated reminders`() {
        val twoDaysAgo = now - 2L * 86_400_000L
        val eightDaysAgo = now - 8L * 86_400_000L
        assertFalse(ServiceReminderMonitor.shouldRemind(800.0, 1_000.0, twoDaysAgo, enabled = true, atMillis = now))
        assertTrue(ServiceReminderMonitor.shouldRemind(800.0, 1_000.0, eightDaysAgo, enabled = true, atMillis = now))
    }

    @Test
    fun `observe reports one reminder inside the cooldown window`() {
        val monitor = ServiceReminderMonitor(InMemoryStore())
        val first = monitor.observe(distanceKm = 900.0, vehicleName = "EQA", enabled = true, atMillis = now)
        assertTrue(first!!.reminderDue)

        val nextDay = now + 86_400_000L
        val second = monitor.observe(distanceKm = 890.0, vehicleName = "EQA", enabled = true, atMillis = nextDay)
        assertFalse(second!!.reminderDue)

        val nextWeek = now + 8L * 86_400_000L
        val third = monitor.observe(distanceKm = 880.0, vehicleName = "EQA", enabled = true, atMillis = nextWeek)
        assertTrue(third!!.reminderDue)
    }

    @Test
    fun `threshold falls back to the default for unknown values`() {
        val store = InMemoryStore()
        val monitor = ServiceReminderMonitor(store)
        assertEquals(ServiceReminderMonitor.DEFAULT_THRESHOLD_KM, monitor.thresholdKm.value, 0.001)

        monitor.setThresholdKm(2_000.0)
        assertEquals(2_000.0, monitor.thresholdKm.value, 0.001)

        // Values outside the offered set are refused, not silently coerced.
        monitor.setThresholdKm(1_234.0)
        assertEquals(2_000.0, monitor.thresholdKm.value, 0.001)

        val reopened = ServiceReminderMonitor(store)
        assertEquals(2_000.0, reopened.thresholdKm.value, 0.001)
    }
}
