package com.simonkaring.voltlink.core.ai

import com.simonkaring.voltlink.core.obd.ObdLogEntry
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Failure modes surfaced to Settings; the messages match the iOS `AILogAnalyzerError` ones. */
sealed class AILogAnalyzerError(message: String) : Exception(message) {
    class MissingApiKey : AILogAnalyzerError("Please provide an API Key in Developer Settings.")
    class InvalidUrl : AILogAnalyzerError("Invalid API URL.")
    class Network(val detail: String) : AILogAnalyzerError("Network error: $detail")
    class InvalidResponse(val statusCode: Int) : AILogAnalyzerError("Server returned HTTP status code $statusCode.")
    class Decoding(val detail: String) : AILogAnalyzerError("Failed to parse AI response: $detail")
    class Api(val detail: String) : AILogAnalyzerError("AI API Error: $detail")
}

data class AIHttpResponse(val statusCode: Int, val body: String)

/** Injectable HTTP hop so provider routing and response parsing are testable on the JVM. */
fun interface AITransport {
    suspend fun post(url: String, headers: Map<String, String>, body: String): AIHttpResponse
}

/**
 * Sends an OBD trace to Gemini (Google AI key) or OpenAI (`sk-` key) and returns the model's
 * analysis. Android counterpart of the iOS `AILogAnalyzer`; the key never leaves the device
 * except in the request header to the chosen provider.
 */
object AILogAnalyzer {
    /// `-latest` aliases keep the analyzer working across provider model retirements.
    const val geminiModel = "gemini-flash-latest"
    const val openAIModel = "gpt-4.1-mini"

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun buildAnalysisPrompt(log: List<ObdLogEntry>, vehicleContext: String = ""): String {
        val text = StringBuilder(
            """
            You are an expert automotive embedded systems engineer specializing in reverse engineering OBD-II (SAE J1979) and UDS (ISO 14229 / ISO 15765-4) CAN bus diagnostics for Electric Vehicles (EVs) and ICE cars.

            Vehicle Context: ${vehicleContext.ifEmpty { "Unknown / Not specified" }}

            Below is a trace of OBD commands sent to the vehicle and the raw hex responses received:

            ---
            """.trimIndent(),
        )

        for (entry in log) {
            text.append("\nTimestamp: ${entry.timestamp}\nSent: ${entry.sent}\nResponse:\n${entry.response}\n")
        }

        text.append(
            """
            ---

            Please analyze the raw response data:
            1. Identify which ECUs/headers responded (e.g. BMS, Powertrain, Inverter, Charger, Gateway).
            2. Identify candidate PIDs/DIDs and positive responses (e.g. `62 xx xx` for UDS Service 0x22, `41 xx` for OBD-II Mode 01).
            3. For key EV metrics (State of Charge %, Pack Voltage, Pack Current / Power kW, Battery Temperatures, 12V Aux Voltage), identify candidate byte positions and formulas (e.g., bit scaling, offsets, signed vs unsigned integers).
            4. Provide a ready-to-use Kotlin decoding snippet or a `VehicleProfile` implementation for VoltLink.
            """.trimIndent(),
        )
        return text.toString()
    }

    /** Chooses the provider from the key shape: OpenAI keys start with `sk-`. */
    fun provider(apiKey: String): Provider =
        if (apiKey.trim().startsWith("sk-")) Provider.OPENAI else Provider.GEMINI

    enum class Provider { GEMINI, OPENAI }

    suspend fun analyze(
        log: List<ObdLogEntry>,
        vehicleContext: String = "",
        apiKey: String,
        transport: AITransport = HttpUrlConnectionTransport,
    ): String {
        val trimmedKey = apiKey.trim()
        if (trimmedKey.isEmpty()) throw AILogAnalyzerError.MissingApiKey()
        if (log.isEmpty()) throw AILogAnalyzerError.Decoding("the OBD log is empty")

        val prompt = buildAnalysisPrompt(log, vehicleContext)
        return when (provider(trimmedKey)) {
            Provider.OPENAI -> queryOpenAI(prompt, trimmedKey, transport)
            Provider.GEMINI -> queryGemini(prompt, trimmedKey, transport)
        }
    }

    private suspend fun queryGemini(prompt: String, apiKey: String, transport: AITransport): String {
        val response = transport.post(
            url = "https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent",
            headers = mapOf(
                "Content-Type" to "application/json",
                // Sent as a header so the key never appears in URLs, proxy logs or crash reports.
                "x-goog-api-key" to apiKey,
            ),
            body = buildJsonObject {
                put(
                    "contents",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("parts", buildJsonArray { add(buildJsonObject { put("text", prompt) }) })
                            },
                        )
                    },
                )
                put("generationConfig", buildJsonObject { put("temperature", 0.2) })
            }.toString(),
        )
        throwForStatus(response)

        val root = parseBody(response)
        val text = root["candidates"]?.jsonArray?.firstOrNull()
            ?.jsonObject?.get("content")?.jsonObject
            ?.get("parts")?.jsonArray?.firstOrNull()
            ?.jsonObject?.get("text")?.jsonPrimitive?.content
        return text ?: throw AILogAnalyzerError.Decoding("Unexpected Gemini response structure.")
    }

    private suspend fun queryOpenAI(prompt: String, apiKey: String, transport: AITransport): String {
        val response = transport.post(
            url = "https://api.openai.com/v1/chat/completions",
            headers = mapOf(
                "Content-Type" to "application/json",
                "Authorization" to "Bearer $apiKey",
            ),
            body = buildJsonObject {
                put("model", openAIModel)
                put(
                    "messages",
                    buildJsonArray {
                        add(
                            buildJsonObject {
                                put("role", "system")
                                put(
                                    "content",
                                    "You are an automotive reverse engineering expert specializing in " +
                                        "OBD-II and UDS CAN bus diagnostic decoding.",
                                )
                            },
                        )
                        add(buildJsonObject { put("role", "user"); put("content", prompt) })
                    },
                )
                put("temperature", 0.2)
            }.toString(),
        )
        throwForStatus(response)

        val root = parseBody(response)
        val text = root["choices"]?.jsonArray?.firstOrNull()
            ?.jsonObject?.get("message")?.jsonObject
            ?.get("content")?.jsonPrimitive?.content
        return text ?: throw AILogAnalyzerError.Decoding("Unexpected OpenAI response structure.")
    }

    private fun parseBody(response: AIHttpResponse): JsonObject =
        runCatching { json.parseToJsonElement(response.body).jsonObject }
            .getOrElse { throw AILogAnalyzerError.Decoding(it.message ?: "invalid JSON") }

    private fun throwForStatus(response: AIHttpResponse) {
        if (response.statusCode == 200) return
        val message = runCatching {
            val root = json.parseToJsonElement(response.body).jsonObject
            root["error"]?.jsonObject?.get("message")?.jsonPrimitive?.content
        }.getOrNull()
        if (message != null) throw AILogAnalyzerError.Api(message)
        throw AILogAnalyzerError.InvalidResponse(response.statusCode)
    }

    /** Default transport: a blocking POST, always invoked from a background dispatcher. */
    object HttpUrlConnectionTransport : AITransport {
        override suspend fun post(url: String, headers: Map<String, String>, body: String): AIHttpResponse {
            val connection = try {
                (URL(url).openConnection() as HttpURLConnection)
            } catch (e: IOException) {
                throw AILogAnalyzerError.InvalidUrl()
            }
            return try {
                connection.requestMethod = "POST"
                connection.connectTimeout = 30_000
                connection.readTimeout = 60_000
                connection.doOutput = true
                headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                connection.outputStream.use { it.write(body.toByteArray()) }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                AIHttpResponse(status, text)
            } catch (e: IOException) {
                throw AILogAnalyzerError.Network(e.message ?: e.javaClass.simpleName)
            } finally {
                connection.disconnect()
            }
        }
    }
}
