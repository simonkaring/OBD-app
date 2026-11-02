package com.simonkaring.voltlink.core.obd

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class IsoTpTest {
    @Test
    fun `cleans prompt and adapter chatter`() {
        val raw = "SEARCHING...\r41 0D 32\r\r>"
        assertEquals("41 0D 32", IsoTp.cleanElmResponse(raw))
    }

    @Test
    fun `single frame keeps headerless payload`() {
        assertEquals(listOf("410D32"), IsoTp.assemblePayloads("41 0D 32\r\n>").map { it.payload })
    }

    @Test
    fun `reassembles multi frame response`() {
        // 10-byte payload 62 60 50 01 02 03 04 05 06 07 split into FF + CF.
        val raw = """
            7E8 10 0A 62 60 50 01 02 03
            7E8 21 04 05 06 07 00 00 00
            >
        """.trimIndent()
        val payloads = IsoTp.assemblePayloads(raw)
        assertEquals(1, payloads.size)
        assertEquals("7E8", payloads[0].ecu)
        assertEquals("6260500102030405060 7".replace(" ", ""), payloads[0].payload)
    }

    @Test
    fun `keeps each ecu payload separate`() {
        val raw = """
            7E8 06 41 0D 32 41 0C 32
            7EA 10 08 62 20 01 00 00
            7EA 21 00 00 00 00 00 00
            >
        """.trimIndent()
        val payloads = IsoTp.assemblePayloads(raw).associate { it.ecu to it.payload }
        assertEquals("410D32410C32", payloads["7E8"])
        assertEquals("6220010000000000", payloads["7EA"])
    }

    @Test
    fun `parses 29 bit headers`() {
        val raw = "18 DA F1 59 06 62 01 0A 0E 6C 00\r\n>"
        val payloads = IsoTp.assemblePayloads(raw)
        assertEquals(1, payloads.size)
        assertEquals("18DAF159", payloads[0].ecu)
        assertEquals("62010A0E6C00", payloads[0].payload)
    }

    @Test
    fun `short single frame invalidates the ecu bucket`() {
        val payloads = IsoTp.assemblePayloads("18 DA F1 59 06 62 01 0B\r\n>")
        assertEquals(0, payloads.size)
    }

    @Test
    fun `out of order consecutive frame invalidates only that ecu`() {
        val raw = """
            7E8 10 0A 62 60 50 01 02 03
            7E8 22 04 05 06 07 00 00 00
            7E9 03 41 0D 32
            >
        """.trimIndent()
        val payloads = IsoTp.assemblePayloads(raw)
        assertEquals(listOf("7E9"), payloads.map { it.ecu })
    }

    @Test
    fun `hex bytes rejects malformed input`() {
        assertArrayEquals(ByteArray(0), IsoTp.hexBytes("ABC"))
        assertArrayEquals(ByteArray(0), IsoTp.hexBytes("ZZ"))
        assertArrayEquals(byteArrayOf(0x01, 0xFF.toByte()), IsoTp.hexBytes("01ff"))
    }

    @Test
    fun `hex bytes after marker ignores trailing odd digit`() {
        val bytes = "6260500102 0304".hexBytesAfter("626050", 4)
        assertTrue(bytes != null)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), bytes)
    }
}
