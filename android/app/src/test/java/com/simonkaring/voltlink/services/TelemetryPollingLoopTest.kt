package com.simonkaring.voltlink.services

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryPollingLoopTest {
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `keeps polling after an unacknowledged control command`() = runTest {
        val sent = mutableListOf<String>()
        val failures = mutableListOf<String>()
        val loop = TelemetryPollingLoop(backgroundScope)
        loop.commands = { listOf("AT CRA 5A4", "22010A") }
        loop.isConnected = { true }
        loop.send = { command ->
            sent += command
            Result.success(if (command.startsWith("AT")) "?" else "62010A0BB8")
        }
        loop.handleControl = { _, result -> result.getOrNull() == "OK" }
        loop.handleControlFailure = { failures += it }
        loop.handleRead = { _, _ -> true }

        loop.start()
        advanceTimeBy(200)

        assertTrue("the refused route is reported", failures.isNotEmpty())
        assertTrue("polling continues after it", sent.count { it == "22010A" } > 0)
        assertTrue(loop.isRunning)
        loop.stop()
        assertEquals(listOf("AT CRA 5A4"), failures.distinct())
    }
}
