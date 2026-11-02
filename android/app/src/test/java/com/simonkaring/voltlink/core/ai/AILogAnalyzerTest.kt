package com.simonkaring.voltlink.core.ai

import com.simonkaring.voltlink.core.obd.ObdLogEntry
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.time.Instant

class AILogAnalyzerTest {
    private val entries = listOf(
        ObdLogEntry(
            timestamp = Instant.parse("2026-10-25T08:15:30Z"),
            sent = "22010A",
            response = "62 01 0A 0F 8C\r\n>",
        ),
        ObdLogEntry(
            timestamp = Instant.parse("2026-10-25T08:15:31Z"),
            sent = "220210",
            response = "62 02 10 04 00 00 39 90\r\n>",
        ),
    )

    private class RecordingTransport(
        private val response: AIHttpResponse,
        private val error: Exception? = null,
    ) : AITransport {
        var url: String = ""
        var headers: Map<String, String> = emptyMap()
        var body: String = ""

        override suspend fun post(url: String, headers: Map<String, String>, body: String): AIHttpResponse {
            this.url = url
            this.headers = headers
            this.body = body
            error?.let { throw it }
            return response
        }
    }

    @Test
    fun promptIncludesVehicleContextAndRawFrames() {
        val prompt = AILogAnalyzer.buildAnalysisPrompt(entries, "Mercedes-Benz EQA 250")

        assertTrue(prompt.contains("Mercedes-Benz EQA 250"))
        assertTrue(prompt.contains("22010A"))
        assertTrue(prompt.contains("62 01 0A 0F 8C"))
        assertTrue(prompt.contains("220210"))
        assertTrue(prompt.contains("62 02 10 04 00 00 39 90"))
        assertTrue(prompt.contains("2026-10-25T08:15:30Z"))
        assertTrue(prompt.contains("Kotlin decoding snippet"))
    }

    @Test
    fun promptFallsBackForUnknownVehicle() {
        val prompt = AILogAnalyzer.buildAnalysisPrompt(entries)
        assertTrue(prompt.contains("Vehicle Context: Unknown / Not specified"))
    }

    @Test
    fun blankKeyFailsBeforeAnyRequest() = runTest {
        val transport = RecordingTransport(AIHttpResponse(200, "{}"))
        try {
            AILogAnalyzer.analyze(entries, apiKey = "   ", transport = transport)
            fail("expected MissingApiKey")
        } catch (e: AILogAnalyzerError.MissingApiKey) {
            assertEquals("Please provide an API Key in Developer Settings.", e.message)
        }
        assertEquals("", transport.url)
    }

    @Test
    fun emptyLogIsRejected() = runTest {
        val transport = RecordingTransport(AIHttpResponse(200, "{}"))
        try {
            AILogAnalyzer.analyze(emptyList(), apiKey = "AIza-test", transport = transport)
            fail("expected Decoding")
        } catch (e: AILogAnalyzerError.Decoding) {
            assertTrue(e.message!!.contains("log is empty"))
        }
    }

    @Test
    fun routesOpenAIKeysAndParsesTheReply() = runTest {
        val transport = RecordingTransport(
            AIHttpResponse(
                200,
                """{"choices":[{"message":{"content":"SOC is byte 4, 0.5 % scale."}}]}""",
            ),
        )

        val result = AILogAnalyzer.analyze(entries, "EQA", "sk-test-key", transport)

        assertEquals("SOC is byte 4, 0.5 % scale.", result)
        assertEquals("https://api.openai.com/v1/chat/completions", transport.url)
        assertEquals("Bearer sk-test-key", transport.headers["Authorization"])
        assertTrue(transport.body.contains(AILogAnalyzer.openAIModel))
        assertTrue(transport.body.contains("22010A"))
    }

    @Test
    fun routesGoogleKeysToGeminiWithoutLeakingTheKeyInTheUrl() = runTest {
        val transport = RecordingTransport(
            AIHttpResponse(
                200,
                """{"candidates":[{"content":{"parts":[{"text":"Pack voltage is bytes 2-3."}]}}]}""",
            ),
        )

        val result = AILogAnalyzer.analyze(entries, "EQA", " AIza-test-key ", transport)

        assertEquals("Pack voltage is bytes 2-3.", result)
        assertTrue(transport.url.contains(AILogAnalyzer.geminiModel))
        assertTrue(transport.url.contains(":generateContent"))
        assertFalse(transport.url.contains("AIza-test-key"))
        assertEquals("AIza-test-key", transport.headers["x-goog-api-key"])
        assertEquals("application/json", transport.headers["Content-Type"])
    }

    @Test
    fun providerErrorsSurfaceTheServerMessage() = runTest {
        val transport = RecordingTransport(
            AIHttpResponse(400, """{"error":{"message":"API key not valid."}}"""),
        )
        try {
            AILogAnalyzer.analyze(entries, "EQA", "AIza-bad", transport)
            fail("expected Api error")
        } catch (e: AILogAnalyzerError.Api) {
            assertEquals("AI API Error: API key not valid.", e.message)
        }
    }

    @Test
    fun statusWithoutAnErrorBodyBecomesInvalidResponse() = runTest {
        val transport = RecordingTransport(AIHttpResponse(503, "upstream unavailable"))
        try {
            AILogAnalyzer.analyze(entries, "EQA", "AIza-busy", transport)
            fail("expected InvalidResponse")
        } catch (e: AILogAnalyzerError.InvalidResponse) {
            assertEquals(503, e.statusCode)
            assertEquals("Server returned HTTP status code 503.", e.message)
        }
    }

    @Test
    fun unexpectedPayloadShapesBecomeDecodingErrors() = runTest {
        val transport = RecordingTransport(AIHttpResponse(200, """{"candidates":[]}"""))
        try {
            AILogAnalyzer.analyze(entries, "EQA", "AIza-empty", transport)
            fail("expected Decoding")
        } catch (e: AILogAnalyzerError.Decoding) {
            assertTrue(e.message!!.contains("Gemini"))
        }
    }

    @Test
    fun transportFailuresBecomeNetworkErrors() = runTest {
        val transport = RecordingTransport(AIHttpResponse(200, ""), error = AILogAnalyzerError.Network("timeout"))
        try {
            AILogAnalyzer.analyze(entries, "EQA", "AIza-timeout", transport)
            fail("expected Network")
        } catch (e: AILogAnalyzerError.Network) {
            assertEquals("Network error: timeout", e.message)
        }
    }
}
