package com.simonkaring.voltlink.core.vehicles

import com.simonkaring.voltlink.core.obd.TelemetryUpdate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.io.File

class AbrpProfileTest {
    companion object {
        private val assetRoot: File? = listOf(
            File("src/main/assets/abrp_pids"),
            File("app/src/main/assets/abrp_pids"),
        ).firstOrNull { it.isDirectory }

        @JvmStatic
        @BeforeClass
        fun installAssets() {
            val root = assetRoot ?: error("assets/abrp_pids not found from ${File(".").absolutePath}")
            AbrpProfileLoader.install { path ->
                val file = root.resolve(path.substringAfterLast('/'))
                if (file.exists()) file.readText() else null
            }
        }
    }

    private fun profile(filename: String): AbrpGenericProfile =
        AbrpProfileLoader.load(filename) as? AbrpGenericProfile
            ?: error("profile $filename did not load from ${assetRoot?.absolutePath}")

    @Test
    fun loadsEveryBundledDefinition() {
        val profiles = AbrpProfileLoader.bundledProfiles()
        assertEquals(AbrpProfileLoader.specs.size, profiles.size)
        val names = profiles.map { it.vehicleName }
        assertTrue(names.any { it.contains("Ford") })
        assertTrue(names.any { it.contains("Hyundai") })
        assertTrue(names.any { it.contains("Volkswagen") })
        assertTrue(profiles.all { it.initializationCommands.isNotEmpty() })
        assertTrue(profiles.all { it.pollingCommands.isNotEmpty() })
    }

    @Test
    fun evaluatesABRPEquationsDynamically() {
        val definition = AbrpDefinitionParser.parse(
            """
            {
              "init_commands": { "command": ["ATZ", "ATSP6"] },
              "data_commands": { "command": ["220101", "220105"] },
              "soc": { "equation": "A*0.5", "command": "220105" },
              "voltage": { "equation": "((A*256)+B)*0.1", "command": "220101" }
            }
            """.trimIndent(),
        )
        assertNotNull(definition)
        val profile = AbrpGenericProfile("Test Vehicle", 75.0, definition!!)

        assertEquals(listOf("ATZ", "ATSP6"), profile.initializationCommands)
        assertEquals(listOf("220101", "220105"), profile.pollingCommands)

        // 62 01 05 C8 -> A = 200 -> 200 * 0.5 = 100 %
        val soc = profile.parseResponse("220105", "62 01 05 C8")
        assertEquals(TelemetryUpdate.Soc(100.0), soc)

        // 62 01 01 0E 74 -> (14*256 + 116) = 3700 -> 370.0 V
        val voltage = profile.parseResponse("220101", "62 01 01 0E 74")
        assertTrue(voltage is TelemetryUpdate.PackVoltage)
        assertEquals(370.0, (voltage as TelemetryUpdate.PackVoltage).volts, 0.1)
    }

    /** A multi-frame reply must decode like the equivalent single frame. */
    @Test
    fun decodesMultiFrameReplyIdenticallyToSingleFrame() {
        val machE = profile("ford_MachE.json")
        val raw = "7E8 10 0A 62 48 F9 FF\r\n7E8 21 9C 00 00 00 00 00\r\n>"
        val update = machE.parseResponse("2248F9", raw)
        assertTrue("expected .packCurrent, got $update", update is TelemetryUpdate.PackCurrent)
        assertEquals(-10.0, (update as TelemetryUpdate.PackCurrent).amps, 0.01)
    }

    /** `Signed()` must work nested inside a larger expression, e.g. `((Signed(K)*256)+L)/10`. */
    @Test
    fun signedFunctionInsideLargerExpression() {
        val ioniq = profile("hkmc_Ioniq5.json")
        val raw = "62 01 01 00 00 00 00 00 00 00 00 00 00 FF 9C\r\n>"
        val update = ioniq.parseResponse("220101", raw)
        assertTrue("expected .packCurrent, got $update", update is TelemetryUpdate.PackCurrent)
        assertEquals(-10.0, (update as TelemetryUpdate.PackCurrent).amps, 0.01)
    }

    @Test
    fun bmwI3AndDeepalProfilesDecode() {
        val i3 = profile("bmw_i3.json")
        val i3Update = i3.parseResponse("22DDBC", "607 05 62 DD BC 02 EE\r\n>")
        assertTrue("expected .soc, got $i3Update", i3Update is TelemetryUpdate.Soc)
        assertEquals(75.0, (i3Update as TelemetryUpdate.Soc).percent, 0.01)

        val deepal = profile("deepal_s05.json")
        val deepalUpdate = deepal.parseResponse("22F228", "7A9 05 62 F2 28 0F A0\r\n>")
        assertTrue("expected .packVoltage, got $deepalUpdate", deepalUpdate is TelemetryUpdate.PackVoltage)
        assertEquals(400.0, (deepalUpdate as TelemetryUpdate.PackVoltage).volts, 0.01)
    }

    @Test
    fun ecuPinningSelectsTheMatchingBucket() {
        // The Mach-E voltage is pinned to 7E4, so the 7E2 reply is ignored when both answer
        // the same DID (a reply from 7E4 alone still decodes).
        val machE = profile("ford_MachE.json")
        // Voltage equation is ((A<<8)+B)*0.01, so 0x9088 is 370.0 V and 0x0C80 only 32.0 V.
        val both = "7E2 05 62 48 0D 0C 80\r\n7E4 05 62 48 0D 90 88\r\n>"
        val update = machE.parseResponse("22480D", both)
        assertTrue("expected .packVoltage, got $update", update is TelemetryUpdate.PackVoltage)
        assertEquals(370.0, (update as TelemetryUpdate.PackVoltage).volts, 0.1)

        val rightEcu = "7E4 05 62 48 0D 90 88\r\n>"
        val single = machE.parseResponse("22480D", rightEcu)
        assertTrue("expected .packVoltage, got $single", single is TelemetryUpdate.PackVoltage)
        assertEquals(370.0, (single as TelemetryUpdate.PackVoltage).volts, 0.1)
    }

    @Test
    fun unsupportedConstructsAreRejectedInsteadOfGuessed() {
        // The iOS evaluator rejects anything that is not arithmetic after substitution.
        assertNull(AbrpExpression.evaluate("A==6", byteArrayOf(6)))
        assertNull(AbrpExpression.evaluate("(A==6)||(A==8)", byteArrayOf(6)))
        assertNull(AbrpExpression.evaluate("Z", byteArrayOf(1)))
        assertEquals(3.0, AbrpExpression.evaluate("1+2", ByteArray(0)) ?: Double.NaN, 0.0001)
    }

    @Test
    fun byteTokensFollowSpreadsheetColumns() {
        assertEquals(0, AbrpExpression.byteIndexForToken("A")!!)
        assertEquals(25, AbrpExpression.byteIndexForToken("Z")!!)
        assertEquals(26, AbrpExpression.byteIndexForToken("AA")!!)
        assertEquals(27, AbrpExpression.byteIndexForToken("ab")!!)
        assertNull(AbrpExpression.byteIndexForToken("A1"))
    }

    @Test
    fun registryResolvesCommunityProfiles() {
        val profile = VehicleProfileId.FORD_MACH_E.makeProfile()
        assertTrue(profile is AbrpGenericProfile)
        assertEquals("Ford Mustang Mach-E", profile.vehicleName)
        assertTrue(VehicleProfileId.FORD_MACH_E.isCommunityProfile)
        assertEquals(
            VehicleProfileId.HYUNDAI_KIA_EGMP,
            VehicleCatalog.profileFor("hkmc_Ioniq5"),
        )
        assertEquals(VehicleProfileId.NISSAN_LEAF_ZE1, VehicleCatalog.profileFor("nissan_leaf"))
    }
}
