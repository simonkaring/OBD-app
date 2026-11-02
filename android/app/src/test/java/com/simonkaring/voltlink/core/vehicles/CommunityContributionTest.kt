package com.simonkaring.voltlink.core.vehicles

import com.simonkaring.voltlink.core.obd.ObdLogEntry
import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import com.simonkaring.voltlink.core.telemetry.TelemetryMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class CommunityContributionTest {
    private val generatedAt = Instant.parse("2026-10-25T10:00:00Z")

    private fun build(logs: List<ObdLogEntry>, profile: VehicleProfile = GenericObd2Profile()) =
        CommunityContributionBuilder.build(
            logs = logs,
            profile = profile,
            vehicleName = "Mercedes-Benz EQA 250 (2021)",
            profileId = "MERCEDES_EQ_A250",
            appVersion = "1.0",
            generatedAt = generatedAt,
        )

    @Test
    fun collectsDecodedCommandsAndCountsObservations() {
        val contribution = build(
            listOf(
                ObdLogEntry(sent = "010d", response = "41 0D 32"),
                ObdLogEntry(sent = "010D", response = "41 0D 40"),
                ObdLogEntry(sent = "0133", response = "41 33 65"),
            ),
        )

        assertEquals(2, contribution.entries.size)
        val speed = contribution.entries.first { it.command == "010D" }
        assertEquals(2, speed.observations)
        // Commands are recorded once, in upper case, with the latest response.
        assertEquals("41 0D 40", speed.response)
        assertEquals(listOf("Speed"), speed.metrics.map { it.name })
        assertEquals("km/h", speed.metrics.single().unit)
        assertEquals(64.0, speed.metrics.single().value, 0.0001)
        assertEquals(2, contribution.metricCount)
    }

    @Test
    fun skipsFailedAndUndecodedCommands() {
        val contribution = build(
            listOf(
                ObdLogEntry(sent = "0105", response = "NO DATA"),
                ObdLogEntry(sent = "22F190", response = "7F 22 31"),
                ObdLogEntry(sent = "010C", response = "41 0C 00 00"),
                ObdLogEntry(sent = "010D", response = "41 0D 32"),
            ),
        )

        // 010C decodes (RPM 0), 0105/22F190 are failures or undecodable.
        assertEquals(listOf("010C", "010D"), contribution.entries.map { it.command })
    }

    @Test
    fun multiValueRepliesContributeEveryMetric() {
        val profile = object : VehicleProfile {
            override val vehicleName = "Fake EV"
            override val isElectricVehicle = true
            override val batteryUsableCapacityKWh = 77.0
            override val initializationCommands = listOf("AT Z")
            override val pollingCommands = listOf("03221E3D55555555")
            override val supportedMetrics = setOf(TelemetryMetric.POWER)
            override fun parseResponse(command: String, rawResponse: String): TelemetryUpdate? =
                parseResponses(command, rawResponse).firstOrNull()

            override fun parseResponses(command: String, rawResponse: String): List<TelemetryUpdate> =
                listOf(TelemetryUpdate.Power(voltage = 400.0, current = 25.0, powerKW = 10.0))
        }

        val contribution = build(listOf(ObdLogEntry(sent = "03221E3D55555555", response = "62 1E 3D")), profile)
        val metrics = contribution.entries.single().metrics

        assertEquals(
            listOf(TelemetryMetric.PACK_CURRENT.displayName, TelemetryMetric.PACK_VOLTAGE.displayName, TelemetryMetric.POWER.displayName),
            metrics.map { it.name },
        )
        assertEquals(10.0, metrics.first { it.name == "Power" }.value, 0.0001)
    }

    @Test
    fun rendersSortedPrettyJson() {
        val contribution = build(listOf(ObdLogEntry(sent = "010D", response = "41 0D 32")))
        val json = contribution.json()

        assertTrue(json.contains("\"schemaVersion\": 1"))
        assertTrue(json.contains("\"generatedAt\": \"2026-10-25T10:00:00Z\""))
        assertTrue(json.contains("\"command\": \"010D\""))
        assertTrue(json.contains("\"value\": 50.0"))
        // Keys stay sorted so diffs of two contributions line up.
        assertTrue(json.indexOf("\"appVersion\"") < json.indexOf("\"entries\""))
        assertTrue(json.indexOf("\"entries\"") < json.indexOf("\"generatedAt\""))
        assertTrue(json.indexOf("\"name\"") < json.indexOf("\"unit\""))
        assertFalse(json.contains("\"\u003c"))
    }

    @Test
    fun filenameSlugMatchesTheIosDocument() {
        val contribution = build(emptyList())
        assertEquals(
            "VoltLink-PID-Contribution-mercedes-benz-eqa-250-2021.json",
            contribution.suggestedFilename,
        )
    }
}
