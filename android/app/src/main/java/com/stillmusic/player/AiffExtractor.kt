package com.stillmusic.player

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.ParserException
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.*
import java.io.InputStream

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class AiffExtractor : Extractor {
    private lateinit var output: ExtractorOutput
    private lateinit var track: TrackOutput
    private var header: AiffHeader? = null
    private val scratch = ByteArray(32768)

    override fun sniff(input: ExtractorInput): Boolean {
        val bytes = ByteArray(12)
        if (!input.peekFully(bytes, 0, bytes.size, true)) return false
        return String(bytes, 0, 4, Charsets.US_ASCII) == "FORM" &&
            String(bytes, 8, 4, Charsets.US_ASCII) in listOf("AIFF", "AIFC")
    }
    override fun init(output: ExtractorOutput) {
        this.output = output
        track = output.track(0, C.TRACK_TYPE_AUDIO)
        output.endTracks()
    }
    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int {
        if (header == null) {
            val info = try {
                AiffHeader.read(object : InputStream() {
                    override fun read(): Int = ByteArray(1).let { if (input.read(it, 0, 1) == -1) -1 else it[0].toInt() and 255 }
                    override fun read(b: ByteArray, off: Int, len: Int) = input.read(b, off, len)
                    override fun skip(n: Long): Long { input.skipFully(n.toInt()); return n }
                })
            } catch (error: Exception) { throw ParserException.createForMalformedContainer("Cannot read this AIFF file", error) }
            header = info
            val encoding = when (info.bits) { 8 -> C.ENCODING_PCM_8BIT; 16 -> C.ENCODING_PCM_16BIT; 24 -> C.ENCODING_PCM_24BIT; else -> C.ENCODING_PCM_32BIT }
            track.format(Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW).setChannelCount(info.channels)
                .setSampleRate(info.sampleRate).setPcmEncoding(encoding).setMaxInputSize(scratch.size).build())
            output.seekMap(ConstantBitrateSeekMap(info.dataStart + info.dataSize, info.dataStart,
                info.sampleRate * info.blockSize * 8, info.blockSize))
        }
        val info = header!!
        val consumed = input.position - info.dataStart
        val remaining = info.dataSize - consumed
        if (remaining <= 0) return Extractor.RESULT_END_OF_INPUT
        val count = minOf(remaining, (scratch.size / info.blockSize * info.blockSize).toLong()).toInt()
        input.readFully(scratch, 0, count)
        aiffToLittleEndian(scratch, count, info.bits, info.littleEndian)
        track.sampleData(ParsableByteArray(scratch, count), count)
        track.sampleMetadata(consumed / info.blockSize * 1_000_000L / info.sampleRate, C.BUFFER_FLAG_KEY_FRAME, count, 0, null)
        return Extractor.RESULT_CONTINUE
    }
    override fun seek(position: Long, timeUs: Long) { if (position == 0L) header = null }
    override fun release() = Unit
}
