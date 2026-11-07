package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class TagWriterTest {
    private val audio = ByteArray(8192) { (it * 31).toByte() }
    private fun rewrite(bytes: ByteArray, format: String, fields: Map<String, String>): ByteArray = ByteArrayOutputStream().also {
        TagWriter.rewrite(bytes.inputStream(), it, format, TagChanges(fields))
    }.toByteArray()
    private fun frame(id: String, text: String): ByteArray {
        val data = byteArrayOf(0) + text.toByteArray()
        return id.toByteArray() + ByteBuffer.allocate(4).putInt(data.size).array() + byteArrayOf(0, 0) + data
    }
    private fun id3(vararg frames: ByteArray): ByteArray {
        val data = frames.fold(byteArrayOf()) { a, b -> a + b }
        val size = data.size
        return "ID3".toByteArray() + byteArrayOf(3, 0, 0, (size shr 21).toByte(), ((size shr 14) and 127).toByte(), ((size shr 7) and 127).toByte(), (size and 127).toByte()) + data
    }
    private fun payload(mp3: ByteArray): ByteArray {
        val length = mp3.sliceArray(6..9).fold(0) { a, b -> (a shl 7) or b.toInt() }
        return mp3.copyOfRange(10 + length, mp3.size)
    }
    @Test fun mp3TextChangesPreserveAudioAndUnselectedFrames() {
        val artist = frame("TPE1", "Untouched artist")
        val picture = frame("APIC", "binary image data")
        val output = rewrite(id3(frame("TIT2", "Old title"), artist, picture) + audio, "mp3", mapOf("TITLE" to "新しい曲"))
        assertArrayEquals(audio, payload(output))
        assertTrue(output.toList().windowed(artist.size).any { it == artist.toList() })
        assertTrue(output.toList().windowed(picture.size).any { it == picture.toList() })
        assertFalse(String(output, Charsets.ISO_8859_1).contains("Old title"))
    }
    @Test fun untaggedMp3AndRepeatedEditsNeverChangeAudio() {
        val first = rewrite(audio, "mp3", mapOf("TITLE" to "First"))
        val second = rewrite(first, "mp3", mapOf("TITLE" to "Second", "ARTIST" to ""))
        assertArrayEquals(audio, payload(first)); assertArrayEquals(audio, payload(second))
    }
    @Test fun unsupportedId3FlagsRefuseWithoutOutput() {
        val bytes = id3(frame("TIT2", "Title")) + audio
        bytes[5] = 0x80.toByte()
        val output = ByteArrayOutputStream()
        try { TagWriter.rewrite(bytes.inputStream(), output, "mp3", TagChanges(mapOf("TITLE" to "New"))); fail() } catch (_: IllegalArgumentException) { }
        assertEquals(0, output.size())
    }
    private fun block(type: Int, bytes: ByteArray, last: Boolean = false) = byteArrayOf((type or if (last) 128 else 0).toByte(), (bytes.size shr 16).toByte(), (bytes.size shr 8).toByte(), bytes.size.toByte()) + bytes
    private fun comments(vararg values: String): ByteArray = ByteArrayOutputStream().also { out ->
        fun number(n: Int) { out.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(n).array()) }
        fun field(value: String) { val bytes = value.toByteArray(); number(bytes.size); out.write(bytes) }
        field("Original vendor"); number(values.size); values.forEach(::field)
    }.toByteArray()
    @Test fun flacPreservesStreamInfoPicturesUnknownCommentsAndAudio() {
        val info = ByteArray(34) { it.toByte() }; val picture = byteArrayOf(7, 8, 9)
        val original = "fLaC".toByteArray() + block(0, info) + block(4, comments("TITLE=Old", "REPLAYGAIN_TRACK_GAIN=-5.2 dB", "ARTIST=Original")) + block(6, picture, true) + audio
        val result = rewrite(original, "flac", mapOf("TITLE" to "New"))
        assertArrayEquals(info, result.copyOfRange(8, 42))
        assertArrayEquals(audio, result.takeLast(audio.size).toByteArray())
        val text = String(result, Charsets.UTF_8)
        assertTrue(text.contains("TITLE=New")); assertTrue(text.contains("ARTIST=Original")); assertTrue(text.contains("REPLAYGAIN_TRACK_GAIN=-5.2 dB")); assertTrue(text.contains("Original vendor"))
        assertTrue(result.toList().windowed(7).any { it == block(6, picture, true).toList() })
    }
    @Test fun malformedFlacAndUnsupportedFormatsAreRejected() {
        for (format in listOf("flac", "m4a")) {
            try { rewrite(audio, format, mapOf("TITLE" to "New")); fail() } catch (_: Exception) { }
        }
    }
}
