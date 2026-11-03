package com.simonkaring.voltlink.services

import org.junit.Assert.assertEquals
import org.junit.Test

class TripLocationCommandTest {
    @Test
    fun `null intent from a sticky restart never starts recording`() {
        // The trip lives in TripTracker, which dies with the process; a restart has
        // nothing to resume, so it must not turn the GPS back on.
        assertEquals(TripLocationCommand.IGNORE, TripLocationCommand.of(null))
    }

    @Test
    fun `explicit start and stop are honoured`() {
        assertEquals(TripLocationCommand.START, TripLocationCommand.of(TripLocationService.ACTION_START))
        assertEquals(TripLocationCommand.STOP, TripLocationCommand.of(TripLocationService.ACTION_STOP))
    }

    @Test
    fun `unknown actions are ignored`() {
        assertEquals(TripLocationCommand.IGNORE, TripLocationCommand.of("com.example.SOMETHING_ELSE"))
    }
}
