package com.stillmusic.player

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.*
import org.junit.Test

class EmbeddedLyricsTest {
    private fun read(data: ByteArray) = EmbeddedLyrics.read(data.size.toLong()) { offset,n -> data.copyOfRange(offset.toInt(),offset.toInt()+n) }
    private fun atom(type: String, data: ByteArray): ByteArray = ByteBuffer.allocate(data.size+8).putInt(data.size+8).put(type.toByteArray(Charsets.ISO_8859_1)).put(data).array()
    @Test fun m4aMetadataAfterLargeAudioIsReadWithoutLoadingAudio() {
        val lyric = atom("©lyr",atom("data",byteArrayOf(0,0,0,1,0,0,0,0)+"Hello".toByteArray()))
        val data = atom("ftyp","M4A ".toByteArray())+atom("mdat",ByteArray(5*1024*1024))+atom("moov",atom("udta",atom("meta",ByteArray(4)+atom("ilst",lyric))))
        assertEquals("Hello",read(data))
    }
    @Test fun mp3UsltUtf8() {
        val text = byteArrayOf(3)+'e'.code.toByte()+'n'.code.toByte()+'g'.code.toByte()+byteArrayOf(0)+"Words".toByteArray()
        val frame = "USLT".toByteArray()+ByteBuffer.allocate(4).putInt(text.size).array()+ByteArray(2)+text
        val id3 = "ID3".toByteArray()+byteArrayOf(3,0,0,0,0,0,frame.size.toByte())
        assertEquals("Words",read(id3+frame))
    }
    @Test fun flacVorbisLyrics() {
        val text = "LYRICS=[00:01]Hello".toByteArray()
        val block = ByteBuffer.allocate(12+text.size).order(ByteOrder.LITTLE_ENDIAN).putInt(0).putInt(1).putInt(text.size).put(text).array()
        val data = "fLaC".toByteArray()+byteArrayOf(0x84.toByte(),0,0,block.size.toByte())+block
        assertEquals("[00:01]Hello",read(data))
    }
    @Test fun malformedAtomDoesNotReadOutsideFile() { assertNull(read(ByteBuffer.allocate(12).putInt(99999).put("moov".toByteArray()).array())) }
    @Test fun missingMetadataReturnsNull() { assertNull(read(atom("ftyp","M4A ".toByteArray()))) }
}
