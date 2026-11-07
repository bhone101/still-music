package com.stillmusic.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.datasource.ByteArrayDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.extractor.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Real app extractors with original tone files; platform decoding still needs device testing. */
@RunWith(AudioHostTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AudioExtractionTest {
    @Test fun mp3ConstantBitrate() = extract("mp3-cbr.mp3", "audio/mpeg")
    @Test fun mp3VariableBitrate() = extract("mp3-vbr.mp3", "audio/mpeg")
    @Test fun aacInM4a() = extract("aac.m4a", "audio/mp4a-latm")
    @Test fun aacAdts() = extract("aac.aac", "audio/mp4a-latm")
    @Test fun alac16() = extract("alac16.m4a", "audio/alac")
    @Test fun alac24() = extract("alac24.m4a", "audio/alac")
    @Test fun flac16() = extract("flac16.flac", "audio/flac")
    @Test fun flac24() = extract("flac24.flac", "audio/flac")
    @Test fun wav16() = extract("pcm16.wav", "audio/raw")
    @Test fun wav24() = extract("pcm24.wav", "audio/raw")
    @Test fun wav32() = extract("pcm32.wav", "audio/raw")
    @Test fun wavFloat32() = extract("float32.wav", "audio/raw")
    @Test fun oggVorbis() = extract("vorbis.ogg", "audio/vorbis")
    @Test fun oggOpus() = extract("opus.opus", "audio/opus")
    @Test fun aiff16() = extract("pcm16.aiff", "audio/raw")
    @Test fun aiff24() = extract("pcm24.aiff", "audio/raw")

    private fun extract(name: String, mime: String) {
        val bytes = checkNotNull(javaClass.getResourceAsStream("/audio/$name")).use { it.readBytes() }
        val source = ByteArrayDataSource(bytes)
        fun input(position: Long): DefaultExtractorInput {
            source.close()
            source.open(DataSpec.Builder().setUri(Uri.EMPTY).setPosition(position).build())
            return DefaultExtractorInput(source, position, bytes.size.toLong())
        }
        val candidates = audioExtractors()
        var current = input(0)
        val extractor = candidates.firstOrNull {
            current.resetPeekPosition()
            // Media3 also treats EOF from an unsuccessful format probe as a
            // non-match, then tries the next extractor with its peek reset.
            try { it.sniff(current) } catch (_: java.io.EOFException) { false }
        }
        assertNotNull("No extractor recognized $name", extractor)
        val output = CapturedAudio()
        try {
            current = input(0)
            extractor!!.init(output)
            val seek = PositionHolder()
            var finished = false
            // Bound the loop so a malformed file cannot hang the regression suite.
            for (step in 0 until 10_000) {
                when (extractor.read(current, seek)) {
                    Extractor.RESULT_END_OF_INPUT -> { finished = true; break }
                    Extractor.RESULT_SEEK -> current = input(seek.position)
                }
            }
            assertTrue("Extraction did not finish: $name", finished)
            assertEquals(name, mime, output.format?.sampleMimeType)
            assertEquals(name, 2, output.format?.channelCount)
            assertEquals(name, 48000, output.format?.sampleRate)
            assertTrue("No audio packets: $name", output.samples > 0)
            assertTrue("Empty audio data: $name", output.bytes > 0)
            assertTrue("No advancing timestamps: $name", output.lastTimeUs > 0)
        } finally {
            candidates.forEach { it.release() }
            source.close()
        }
    }

    private class CapturedAudio : ExtractorOutput, TrackOutput {
        var format: Format? = null
        var samples = 0
        var bytes = 0L
        var lastTimeUs = 0L
        override fun track(id: Int, type: Int): TrackOutput =
            if (type == C.TRACK_TYPE_AUDIO) this else DiscardingTrackOutput()
        override fun endTracks() {}
        override fun seekMap(seekMap: SeekMap) {}
        override fun format(format: Format) { this.format = format }
        override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean, sampleDataPart: Int): Int {
            val count = input.read(ByteArray(minOf(length, 32768)), 0, minOf(length, 32768))
            if (count == -1 && !allowEndOfInput) throw java.io.EOFException()
            if (count > 0) bytes += count
            return count
        }
        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
            bytes += length
            data.skipBytes(length)
        }
        override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
            assertTrue("Empty audio packet", size > 0)
            samples++
            lastTimeUs = maxOf(lastTimeUs, timeUs)
        }
    }
}
