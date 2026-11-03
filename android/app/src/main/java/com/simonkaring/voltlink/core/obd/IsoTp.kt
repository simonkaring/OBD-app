package com.simonkaring.voltlink.core.obd

/**
 * ISO 15765-4 (ISO-TP) frame reassembly for multi-line ELM327 CAN responses.
 *
 * Port of the iOS `ISO15765Parser`: a second ECU's First Frame must not clobber another
 * ECU's in-flight message, and an out-of-order Consecutive Frame invalidates only that
 * ECU's bucket. Every responding ECU keeps its own payload, in arrival order.
 */
object IsoTp {
    /** CAN identifier bucket for lines carrying no header at all (e.g. `AT H0`). */
    const val HEADERLESS_ECU = ""

    data class EcuPayload(val ecu: String, val payload: String)

    /** Cleans a raw ELM327 response: prompt, line endings and adapter chatter removed. */
    fun cleanElmResponse(raw: String): String {
        val text = raw
            .replace(">", "")
            .replace("\r", "\n")
            .replace("SEARCHING...", "")
            .replace("BUS INIT...", "")
            .replace("STOPPED", "")
            .trim()
        return text.split("\n").filter { it.isNotEmpty() }.joinToString("\n")
    }

    /** Concatenates every responding ECU's payload; prefer [assemblePayloads] when the ECU matters. */
    fun assemblePayload(rawResponse: String): String =
        assemblePayloads(rawResponse).joinToString("") { it.payload }

    /** Parses a compact hex string (whitespace ignored); odd-length or non-hex input yields []. */
    fun hexBytes(hex: String): ByteArray {
        val clean = hex.replace(" ", "").replace("\r", "").replace("\n", "")
        if (clean.length % 2 != 0) return ByteArray(0)
        val result = ByteArray(clean.length / 2)
        for (index in result.indices) {
            result[index] = clean.substring(index * 2, index * 2 + 2).toUByteOrNull(16)?.toByte() ?: return ByteArray(0)
        }
        return result
    }

    private class Bucket {
        var payloadHex = StringBuilder()
        var multiFrameStart: Int? = null
        var multiFrameHexLength: Int? = null
        var expectedSeq: Int? = null
        var isInvalid = false
    }

    fun assemblePayloads(rawResponse: String): List<EcuPayload> {
        val lines = cleanElmResponse(rawResponse).split("\n")
        val buckets = LinkedHashMap<String, Bucket>()

        for (line in lines) {
            val tokens = line.split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (tokens.isEmpty()) continue

            var hexTokens = tokens
            var ecuKey = HEADERLESS_ECU
            val looksLike29BitPrefix = tokens.size >= 4 &&
                tokens[0].uppercase() in setOf("18", "19") &&
                tokens.subList(1, 4).all { it.length == 2 && it.toUByteOrNull(16) != null }
            when {
                looksLike29BitPrefix -> {
                    hexTokens = tokens.drop(4)
                    ecuKey = tokens.subList(0, 4).joinToString("").uppercase()
                }
                (tokens[0].length == 3 || tokens[0].length == 8) && tokens[0].isHexToken() -> {
                    // 3 hex chars = 11-bit CAN ID (7E8); 8 hex chars = a 29-bit ID printed
                    // as one token, which is what `AT CAF 0` yields (e.g. 17FE007B).
                    hexTokens = tokens.drop(1)
                    ecuKey = tokens[0].uppercase()
                }
            }

            // Headerless non-hex lines are adapter chatter, not CAN frames.
            if (ecuKey == HEADERLESS_ECU && hexTokens.isNotEmpty() && hexTokens[0].toUByteOrNull(16) == null) continue

            val bucket = buckets.getOrPut(ecuKey) { Bucket() }
            if (bucket.isInvalid) continue

            val bytesOk = hexTokens.isNotEmpty() && hexTokens.all { token -> token.length == 2 && token.isHexToken() }
            val firstByte = if (bytesOk) hexTokens[0].toUByteOrNull(16) else null
            if (!bytesOk || firstByte == null) {
                bucket.isInvalid = true
                continue
            }

            val frameType = (firstByte.toInt() and 0xF0) shr 4
            // Only CFs (or a payload-free flow control) may follow an unfinished FF.
            if (bucket.expectedSeq != null && frameType != 2 && frameType != 3) {
                bucket.isInvalid = true
                continue
            }

            when (frameType) {
                0 -> { // Single Frame
                    val length = firstByte.toInt() and 0x0F
                    if (length !in 1..7 || hexTokens.size < 1 + length) {
                        bucket.isInvalid = true
                        continue
                    }
                    bucket.payloadHex.append(hexTokens.subList(1, 1 + length).joinToString(""))
                }
                1 -> { // First Frame, 12-bit total length
                    if (hexTokens.size <= 2) {
                        bucket.isInvalid = true
                        continue
                    }
                    val lowLength = hexTokens[1].toUByteOrNull(16)
                    if (lowLength == null) {
                        bucket.isInvalid = true
                        continue
                    }
                    val totalLength = ((firstByte.toInt() and 0x0F) shl 8) or lowLength.toInt()
                    if (totalLength <= hexTokens.size - 2) {
                        bucket.isInvalid = true
                        continue
                    }
                    bucket.multiFrameStart = bucket.payloadHex.length
                    bucket.multiFrameHexLength = totalLength * 2
                    bucket.expectedSeq = 1
                    bucket.payloadHex.append(hexTokens.drop(2).joinToString(""))
                }
                2 -> { // Consecutive Frame
                    val expected = bucket.expectedSeq
                    val start = bucket.multiFrameStart
                    val length = bucket.multiFrameHexLength
                    val seq = firstByte.toInt() and 0x0F
                    if (expected == null || start == null || length == null || seq != (expected and 0x0F) || hexTokens.size <= 1) {
                        bucket.isInvalid = true
                        continue
                    }
                    bucket.expectedSeq = expected + 1
                    bucket.payloadHex.append(hexTokens.drop(1).joinToString(""))
                    if (bucket.payloadHex.length >= start + length) {
                        // Trim final-frame padding now, so a later message cannot fill a gap.
                        bucket.payloadHex.setLength(start + length)
                        bucket.multiFrameStart = null
                        bucket.multiFrameHexLength = null
                        bucket.expectedSeq = null
                    }
                }
                3 -> continue // Flow Control carries no payload.
                else -> bucket.payloadHex.append(hexTokens.joinToString(""))
            }
        }

        return buckets.mapNotNull { (ecu, bucket) ->
            if (bucket.isInvalid || bucket.expectedSeq != null || bucket.payloadHex.isEmpty()) {
                null
            } else {
                EcuPayload(ecu, bucket.payloadHex.toString())
            }
        }
    }
}

/** Whole hex bytes following [marker] in an already assembled payload. */
fun String.hexBytesAfter(marker: String): ByteArray? {
    // The marker must start on a byte boundary: a plain substring search would match
    // "62F190" inside "A62F190B" at half a byte and shift every value by one byte.
    var index = 0
    while (index + marker.length <= length) {
        if (regionMatches(index, marker, 0, marker.length)) {
            val suffix = substring(index + marker.length).filterNot { it.isWhitespace() }
            val evenCount = suffix.length - suffix.length % 2
            if (evenCount == 0) return ByteArray(0)
            return IsoTp.hexBytes(suffix.substring(0, evenCount))
        }
        index += 2
    }
    return null
}

/** True when every character is an ASCII hex digit. */
private fun String.isHexToken(): Boolean =
    isNotEmpty() && all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }

/** As [hexBytesAfter], but requires and returns exactly [count] leading bytes. */
fun String.hexBytesAfter(marker: String, count: Int): ByteArray? {
    val bytes = hexBytesAfter(marker) ?: return null
    if (bytes.size < count) return null
    return bytes.copyOfRange(0, count)
}

fun String.hexByteAfter(marker: String): Int? = hexBytesAfter(marker, 1)?.get(0)?.toInt()?.and(0xFF)
