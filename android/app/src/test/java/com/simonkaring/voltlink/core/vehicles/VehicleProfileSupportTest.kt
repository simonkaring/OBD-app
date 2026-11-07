package com.simonkaring.voltlink.core.vehicles

import org.junit.Assert.assertEquals
import org.junit.Test

class VehicleProfileSupportTest {
    @Test
    fun `support label follows the decoder source`() {
        assertEquals(TelemetrySupport.VERIFIED.label, VehicleProfileId.MERCEDES_EQ_A250.supportLabel)
        assertEquals(TelemetrySupport.COMMUNITY.label, VehicleProfileId.MERCEDES_EQ_A_OBDb.supportLabel)
        assertEquals(TelemetrySupport.COMMUNITY.label, VehicleProfileId.FORD_MACH_E.supportLabel)
        assertEquals(TelemetrySupport.GENERIC.label, VehicleProfileId.GENERIC_OBD2.supportLabel)
        assertEquals(TelemetrySupport.GENERIC.label, VehicleProfileId.GENERIC_EV.supportLabel)
    }
}
