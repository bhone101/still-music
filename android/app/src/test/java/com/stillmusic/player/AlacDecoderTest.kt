package com.stillmusic.player

import com.beatofthedrum.alacdecoder.AlacPacketDecoder
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import org.junit.Assert.*
import org.junit.Test

class AlacDecoderTest {
    private fun resource(name: String) = javaClass.getResourceAsStream("/alac/$name")!!.use { it.readBytes() }
    private fun packets(name: String): List<ByteArray> = DataInputStream(resource("$name.packets").inputStream()).use { input ->
        buildList { while (input.available() > 0) add(ByteArray(input.readInt()).also(input::readFully)) }
    }
    private fun verify(name: String) {
        val decoder = AlacPacketDecoder(resource("$name.config"))
        val output = ByteArrayOutputStream()
        packets(name).forEach { output.write(decoder.decode(it)) }
        assertArrayEquals(resource("$name.pcm"), output.toByteArray())
    }
    @Test fun stereo16bit44100() = verify("16bit-2ch-44100")
    @Test fun stereo24bit96000() = verify("24bit-2ch-96000")
    @Test fun mono16bit48000() = verify("16bit-1ch-48000")
    @Test fun mono24bit44100() = verify("24bit-1ch-44100")
    @Test fun seekingDoesNotReusePredictionFromPreviousPacket() {
        val config = resource("24bit-2ch-96000.config")
        val packets = packets("24bit-2ch-96000")
        val decoder = AlacPacketDecoder(config)
        packets.forEach { decoder.decode(it) }
        assertArrayEquals(AlacPacketDecoder(config).decode(packets[1]), decoder.decode(packets[1]))
    }
    @Test fun oversizedFrameConfigurationIsRejected() {
        val config = resource("16bit-2ch-44100.config")
        config[0] = 0x7f
        assertThrows(IllegalArgumentException::class.java) { AlacPacketDecoder(config) }
    }
    @Test fun truncatedPacketIsRejected() {
        val decoder = AlacPacketDecoder(resource("16bit-2ch-44100.config"))
        assertThrows(RuntimeException::class.java) { decoder.decode(byteArrayOf(0x20, 0, 0)) }
    }
}
