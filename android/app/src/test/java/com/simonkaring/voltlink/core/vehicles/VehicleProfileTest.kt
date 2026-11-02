package com.simonkaring.voltlink.core.vehicles

import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class VehicleProfileTest {
    @Test
    fun `generic profile decodes speed rpm and coolant`() {
        val profile = GenericObd2Profile()
        assertEquals(TelemetryUpdate.Speed(50.0), profile.parseResponse("010D", "41 0D 32\r\n>"))
        assertEquals(
            TelemetryUpdate.MotorStats(2000.0, 0.0),
            profile.parseResponse("010C", "41 0C 1F 40\r\n>"),
        )
        assertEquals(
            TelemetryUpdate.CoolantTemp(88.0),
            profile.parseResponse("0105", "41 05 80\r\n>"),
        )
    }

    @Test
    fun `generic profile tolerates spaces in command`() {
        val profile = GenericObd2Profile()
        assertEquals(TelemetryUpdate.Speed(50.0), profile.parseResponse("01 0D", "41 0D 32\r\n>"))
    }

    @Test
    fun `generic profile returns null for negative response`() {
        val profile = GenericObd2Profile()
        assertNull(profile.parseResponse("010D", "NO DATA\r\n>"))
    }

    @Test
    fun `eqa pack voltage uses 29 bit uds reply`() {
        val profile = MercedesEqa250Profile()
        val update = profile.parseResponse("22010A", "18 DA F1 59 06 62 01 0A 0E 6C 00\r\n>") as TelemetryUpdate.PackVoltage
        assertEquals(369.2, update.volts, 1e-9)
    }

    @Test
    fun `eqa leaves unvalidated did undecoded`() {
        val profile = MercedesEqa250Profile()
        assertNull(profile.parseResponse("220210", "62 02 10 04 00 00 00 00\r\n>"))
    }

    @Test
    fun `eqa obdb decodes soc and pack current sign`() {
        val profile = MercedesEqaObdbProfile()
        assertEquals(
            TelemetryUpdate.Soc(78.5),
            profile.parseResponse("226050", "7ED 05 62 60 50 1E AA\r\n>"),
        )
        assertEquals(
            TelemetryUpdate.PackCurrent(-55.0),
            profile.parseResponse("226053", "7ED 05 62 60 53 02 26\r\n>"),
        )
    }

    @Test
    fun `eqa obdb emits wheel speeds from one payload`() {
        val profile = MercedesEqaObdbProfile()
        val updates = profile.parseResponses(
            "222001",
            "7EA 10 0A 62 20 01 03 20 03 21 03 22\r\n7EA 21 03 23 00 00 00 00 00\r\n>",
        )
        assertEquals(TelemetryUpdate.Speed(45.0), updates.first())
        assertTrue(updates.any { it is TelemetryUpdate.CommunityMetric })
    }

    @Test
    fun `eqa obdb rejects implausible soc`() {
        val profile = MercedesEqaObdbProfile()
        assertNull(profile.parseResponse("226050", "7ED 04 62 60 50 FF FF\r\n>"))
    }

    @Test
    fun `volkswagen meb decodes voltage soc and current`() {
        val profile = VolkswagenMebProfile()
        val voltage = profile.parseResponse("03221E3B55555555", "62 1E 3B 06 22\r\n>") as TelemetryUpdate.PackVoltage
        assertEquals(392.5, voltage.volts, 1e-9)
        // (1.12 * 191 / 2.5) - 7.16 = 78.408 %
        val soc = profile.parseResponse("0322028C55555555", "62 02 8C BF\r\n>") as TelemetryUpdate.Soc
        assertEquals(78.408, soc.percent, 1e-6)
        // raw 149000 -> 10 A into the pack (negative current = charging)
        val current = profile.parseResponse("03221E3D55555555", "62 1E 3D 00 02 46 08\r\n>") as TelemetryUpdate.PackCurrent
        assertEquals(10.0, current.amps, 1e-9)
    }

    @Test
    fun `volkswagen meb reports charging with unknown rate`() {
        val profile = VolkswagenMebProfile()
        val update = profile.parseResponse("0322744855555555", "62 74 48 04\r\n>") as TelemetryUpdate.ChargingStats
        assertNull(update.kwRate)
        assertEquals("AC", update.acOrDc)
    }

    @Test
    fun `registry resolves each profile`() {
        // ABRP profiles read their documents from the assets; install a file-backed reader so
        // this resolves what the app resolves at runtime instead of the generic fallback.
        val root = listOf(File("src/main/assets/abrp_pids"), File("app/src/main/assets/abrp_pids"))
            .firstOrNull { it.isDirectory }
        assertTrue("assets/abrp_pids not found", root != null)
        AbrpProfileLoader.install { path ->
            root!!.resolve(path.substringAfterLast('/')).takeIf { it.exists() }?.readText()
        }

        VehicleProfileId.entries.forEach { id ->
            val profile = id.makeProfile()
            if (id.isCommunityProfile) {
                // The picker labels community decoders with their source, e.g. "(ABRP)".
                assertTrue(
                    "${id.name} resolved to ${profile.vehicleName}",
                    id.displayName.startsWith(profile.vehicleName),
                )
                assertTrue("${id.name} should load its ABRP document", profile is AbrpGenericProfile)
            } else {
                assertEquals(id.displayName, profile.vehicleName)
            }
        }
    }
}
