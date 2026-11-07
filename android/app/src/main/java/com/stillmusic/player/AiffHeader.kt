package com.stillmusic.player

import java.io.DataInputStream
import java.io.InputStream
import kotlin.math.pow

internal data class AiffHeader(val channels: Int, val sampleRate: Int, val bits: Int,
    val frames: Long, val dataStart: Long, val littleEndian: Boolean) {
    val blockSize: Int get() = channels * (bits / 8)
    val dataSize: Long get() = frames * blockSize

    companion object {
        fun read(source: InputStream): AiffHeader {
            val input = DataInputStream(source)
            fun fourCC() = String(ByteArray(4).also(input::readFully), Charsets.US_ASCII)
            fun uint() = input.readInt().toLong() and 0xffffffffL
            require(fourCC() == "FORM") { "Missing AIFF FORM" }
            val formEnd = uint() + 8
            val type = fourCC()
            require(type == "AIFF" || type == "AIFC") { "Unsupported AIFF container" }
            var position = 12L
            var channels = 0; var rate = 0; var bits = 0; var frames = 0L
            var littleEndian = false
            while (position + 8 <= formEnd) {
                val chunk = fourCC(); val size = uint(); position += 8
                require(size <= formEnd - position) { "Invalid AIFF chunk size" }
                if (chunk == "SSND") {
                    require(channels > 0 && size >= 8) { "Missing AIFF format information" }
                    val offset = uint(); uint(); position += 8
                    require(offset <= size - 8 && offset <= Int.MAX_VALUE) { "Invalid AIFF sound offset" }
                    input.skipN(offset.toInt()); position += offset
                    val header = AiffHeader(channels, rate, bits, frames, position, littleEndian)
                    require(header.dataSize <= size - 8 - offset) { "Truncated AIFF samples" }
                    return header
                }
                // Header chunks are bounded; audio itself is streamed without this size restriction.
                require(size <= 32 * 1024 * 1024) { "AIFF header chunk is too large" }
                if (chunk == "COMM") {
                    require(size >= if (type == "AIFC") 22 else 18) { "Invalid AIFF COMM" }
                    channels = input.readUnsignedShort(); frames = uint(); bits = input.readUnsignedShort()
                    val exponent = input.readUnsignedShort()
                    val high = uint(); val low = uint()
                    require(exponent and 0x8000 == 0) { "Invalid AIFF sample rate" }
                    val sampleRate = (high * 4294967296.0 + low) * 2.0.pow(exponent - 16383 - 63)
                    require(sampleRate.isFinite() && sampleRate in 8000.0..384000.0 && sampleRate == sampleRate.toInt().toDouble()) { "Unsupported AIFF sample rate" }
                    rate = sampleRate.toInt()
                    require(channels in 1..8 && bits in listOf(8, 16, 24, 32)) { "Unsupported AIFF PCM format" }
                    var used = 18
                    if (type == "AIFC") {
                        val compression = fourCC(); used += 4
                        require(compression in listOf("NONE", "twos", "sowt")) { "Compressed AIFF is not supported" }
                        littleEndian = compression == "sowt"
                    }
                    input.skipN(size.toInt() - used)
                } else input.skipN(size.toInt())
                position += size
                if (size and 1L != 0L) { input.readUnsignedByte(); position++ }
            }
            error("AIFF has no sound data")
        }
        private fun DataInputStream.skipN(count: Int) {
            var remaining = count
            while (remaining > 0) {
                val skipped = skipBytes(remaining)
                if (skipped == 0) { readByte(); remaining-- } else remaining -= skipped
            }
        }
    }
}

internal fun aiffToLittleEndian(bytes: ByteArray, count: Int, bits: Int, littleEndian: Boolean) {
    val width = bits / 8
    require(count % width == 0)
    if (bits == 8) {
        for (i in 0 until count) bytes[i] = (bytes[i].toInt() xor 0x80).toByte()
    } else if (!littleEndian) {
        for (i in 0 until count step width) for (j in 0 until width / 2) {
            val swap = bytes[i + j]; bytes[i + j] = bytes[i + width - j - 1]; bytes[i + width - j - 1] = swap
        }
    }
}
