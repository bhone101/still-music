package com.stillmusic.player

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import org.junit.Assert.*
import org.junit.Test

class AiffHeaderTest {
    private fun fixture(compression: String? = null, soundBytes: Int = 8, offset: Int = 0): ByteArray {
        fun chunk(id: String, data: ByteArray): ByteArray = ByteArrayOutputStream().also { bytes ->
            DataOutputStream(bytes).apply { writeBytes(id); writeInt(data.size); write(data); if (data.size % 2 != 0) writeByte(0) }
        }.toByteArray()
        val comm = ByteArrayOutputStream().also { bytes -> DataOutputStream(bytes).apply {
            writeShort(2); writeInt(2); writeShort(16)
            // IEEE extended 80-bit representation of 44100 Hz.
            writeShort(16383 + 15); writeLong(44100L shl 48)
            compression?.let { writeBytes(it) }
        } }.toByteArray()
        val sound = ByteArrayOutputStream().also { bytes -> DataOutputStream(bytes).apply {
            writeInt(offset); writeInt(0); write(ByteArray(offset)); write(ByteArray(soundBytes))
        } }.toByteArray()
        val body = ByteArrayOutputStream().also {
            it.write((if (compression == null) "AIFF" else "AIFC").toByteArray())
            it.write(chunk("NAME", byteArrayOf(1, 2, 3))) // odd-sized metadata requires padding
            it.write(chunk("COMM", comm)); it.write(chunk("SSND", sound))
        }.toByteArray()
        return chunk("FORM", body)
    }
    @Test fun parsesPaddedMetadataAndSoundOffset() {
        val bytes = fixture(offset = 5)
        val header = AiffHeader.read(bytes.inputStream())
        assertEquals(44100, header.sampleRate)
        assertEquals(2, header.channels)
        assertEquals(16, header.bits)
        assertEquals(8, header.dataSize.toInt())
        assertEquals(bytes.size - 9, header.dataStart.toInt()) // SSND odd-byte padding follows samples
    }
    @Test fun recognizesLittleEndianAifc() {
        assertTrue(AiffHeader.read(fixture("sowt").inputStream()).littleEndian)
        assertFalse(AiffHeader.read(fixture("NONE").inputStream()).littleEndian)
    }
    @Test fun rejectsCompressedAndTruncatedAudio() {
        assertThrows(IllegalArgumentException::class.java) { AiffHeader.read(fixture("ima4").inputStream()) }
        assertThrows(IllegalArgumentException::class.java) { AiffHeader.read(fixture(soundBytes = 4).inputStream()) }
    }
    @Test fun convertsIntegerPcmWithoutChangingSampleValues() {
        for (bits in listOf(16, 24, 32)) {
            val width = bits / 8
            val original = ByteArray(width * 2) { (it + 1).toByte() }
            val converted = original.copyOf()
            aiffToLittleEndian(converted, converted.size, bits, false)
            assertArrayEquals(original.take(width).reversed().toByteArray() + original.drop(width).reversed().toByteArray(), converted)
            val little = original.copyOf()
            aiffToLittleEndian(little, little.size, bits, true)
            assertArrayEquals(original, little)
        }
    }
    @Test fun signed8bitBecomesUnsignedPcm() {
        val bytes = byteArrayOf(-128, -1, 0, 127)
        aiffToLittleEndian(bytes, bytes.size, 8, false)
        assertArrayEquals(byteArrayOf(0, 127, -128, -1), bytes)
    }
}
