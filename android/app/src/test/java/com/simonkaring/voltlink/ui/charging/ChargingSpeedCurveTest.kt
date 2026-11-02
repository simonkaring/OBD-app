package com.simonkaring.voltlink.ui.charging

import com.simonkaring.voltlink.data.ChargingSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ChargingSpeedCurveTest {
    private val origin = Instant.parse("2026-05-01T10:00:00Z")

    private fun sample(seconds: Long, powerKW: Double, socPct: Double) =
        ChargingSample(timestamp = origin.plusSeconds(seconds), socPct = socPct, powerKW = powerKW)

    @Test
    fun `minutes are elapsed from the first reading and power is clamped`() {
        val points = ChargingSpeedCurve.session(
            listOf(
                sample(0, 45.0, 30.0),
                sample(120, -3.0, 0.0),
                sample(240, 120.0, 55.0),
            ),
        )

        assertEquals(listOf(0.0, 2.0, 4.0), points.map { it.minute })
        assertEquals(listOf(45.0, 0.0, 120.0), points.map { it.powerKW })
        assertNull(points[1].socPct)
    }

    @Test
    fun `samples are ordered by time and need at least two points`() {
        assertTrue(ChargingSpeedCurve.session(listOf(sample(0, 10.0, 10.0))).isEmpty())

        val points = ChargingSpeedCurve.session(
            listOf(sample(120, 20.0, 40.0), sample(0, 40.0, 20.0)),
        )
        assertEquals(listOf(40.0, 20.0), points.map { it.powerKW })
        assertEquals(listOf(0.0, 2.0), points.map { it.minute })
    }

    @Test
    fun `long sessions are downsampled to the requested resolution`() {
        val samples = (0 until 400).map { index -> sample(index * 10L, 100.0 - index * 0.1, index / 4.0) }

        val points = ChargingSpeedCurve.session(samples, limit = 60)

        assertEquals(60, points.size)
        assertEquals(0.0, points.first().minute, 1e-9)
    }

    @Test
    fun `elapsed formatting stays human readable`() {
        assertEquals("—", formatElapsed(0.0))
        assertEquals("5 min", formatElapsed(300.0))
        assertEquals("1 h 05 min", formatElapsed(3900.0))
    }
}
