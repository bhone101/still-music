package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer

class Mp4MetadataTest {
    private fun atom(type: String, payload: ByteArray): ByteArray = ByteBuffer.allocate(payload.size+8).putInt(payload.size+8).put(type.toByteArray(Charsets.ISO_8859_1)).put(payload).array()
    private fun read(data: ByteArray) = Mp4Metadata.read(data.size.toLong()) { at,count -> data.copyOfRange(at.toInt(), at.toInt()+count) }
    @Test fun realAacAndAlacDurationsAreReadWithoutPlatformDecoder() {
        listOf("aac.m4a", "alac16.m4a", "alac24.m4a").forEach { name ->
            val data = checkNotNull(javaClass.getResourceAsStream("/audio/$name")).use { it.readBytes() }
            assertTrue("$name duration was missing", read(data).duration in 100..10000)
        }
    }
    @Test fun versionZeroMovieHeaderAndTextTags() {
        val header = ByteBuffer.allocate(20).putInt(0).putInt(0).putInt(0).putInt(48000).putInt(48000*180).array()
        fun tag(type: String, text: String) = atom(type, atom("data", ByteBuffer.allocate(8).putInt(1).putInt(0).array()+text.toByteArray()))
        val tags = atom("udta", atom("meta", ByteArray(4)+atom("ilst", tag("©nam", "A song")+tag("©ART", "An artist"))))
        val result = read(atom("moov",atom("mvhd",header)+tags))
        assertEquals(180000L,result.duration); assertEquals("A song", result.title); assertEquals("An artist", result.artist)
    }
    @Test fun versionOneAndAudioTrackFallback() {
        val header = ByteBuffer.allocate(32).putInt(1 shl 24).putLong(0).putLong(0).putInt(1000).putLong(123456).array()
        val handler = ByteArray(8)+"soun".toByteArray()
        assertEquals(123456L,read(atom("moov",atom("trak",atom("mdia",atom("mdhd",header)+atom("hdlr",handler))))).duration)
    }
    @Test fun skipsLargeAudioPayloadWithoutReadingIt() {
        val header = ByteBuffer.allocate(20).putInt(0).putInt(0).putInt(0).putInt(1000).putInt(10000).array()
        val prefix = atom("mdat",ByteArray(2000000))
        val data = prefix+atom("moov",atom("mvhd",header))
        var total = 0
        val result = Mp4Metadata.read(data.size.toLong()) { at,count -> total += count; data.copyOfRange(at.toInt(),at.toInt()+count) }
        assertEquals(10000L,result.duration); assertTrue(total < 100)
    }
    @Test fun invalidAtomBoundsAreRejected() {
        try { read(ByteBuffer.allocate(8).putInt(10000).put("moov".toByteArray()).array()); fail("Malformed size accepted") } catch (_: IllegalArgumentException) { }
    }
}
