package com.stillmusic.player;

import android.os.Handler;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.decoder.CryptoConfig;
import androidx.media3.decoder.DecoderException;
import androidx.media3.decoder.DecoderInputBuffer;
import androidx.media3.decoder.SimpleDecoder;
import androidx.media3.decoder.SimpleDecoderOutputBuffer;
import androidx.media3.exoplayer.audio.AudioRendererEventListener;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DecoderAudioRenderer;
import com.beatofthedrum.alacdecoder.AlacPacketDecoder;
import java.nio.ByteBuffer;

/** Software fallback for Apple Lossless in M4A; AAC and other codecs retain platform decoding. */
@UnstableApi
public final class AlacAudioRenderer extends DecoderAudioRenderer<AlacAudioRenderer.PacketDecoder> {
    public AlacAudioRenderer(Handler handler, AudioRendererEventListener listener, AudioSink sink) {
        super(handler, listener, sink);
    }
    @Override public String getName() { return "StillAlacAudioRenderer"; }
    @Override protected int supportsFormatInternal(Format format) {
        if (!MimeTypes.AUDIO_ALAC.equals(format.sampleMimeType)) return C.FORMAT_UNSUPPORTED_TYPE;
        if (format.cryptoType != C.CRYPTO_TYPE_NONE) return C.FORMAT_UNSUPPORTED_DRM;
        try {
            AlacPacketDecoder decoder = config(format);
            return sinkSupportsFormat(outputFormat(decoder)) ? C.FORMAT_HANDLED : C.FORMAT_UNSUPPORTED_SUBTYPE;
        } catch (IllegalArgumentException error) { return C.FORMAT_UNSUPPORTED_SUBTYPE; }
    }
    private static AlacPacketDecoder config(Format format) {
        if (format.initializationData.size() != 1) throw new IllegalArgumentException("Missing ALAC configuration");
        return new AlacPacketDecoder(format.initializationData.get(0));
    }
    private static Format outputFormat(AlacPacketDecoder decoder) {
        return new Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setChannelCount(decoder.channels).setSampleRate(decoder.sampleRate)
                .setPcmEncoding(C.ENCODING_PCM_16BIT).build();
    }
    @Override protected PacketDecoder createDecoder(Format format, CryptoConfig cryptoConfig) throws DecodeError {
        try { return new PacketDecoder(config(format)); }
        catch (IllegalArgumentException error) { throw new DecodeError(error); }
    }
    @Override protected Format getOutputFormat(PacketDecoder decoder) { return outputFormat(decoder.codec); }

    public static final class DecodeError extends DecoderException {
        DecodeError(Throwable cause) { super("Cannot decode this Apple Lossless file", cause); }
    }
    public static final class PacketDecoder extends SimpleDecoder<DecoderInputBuffer, SimpleDecoderOutputBuffer, DecodeError> {
        final AlacPacketDecoder codec;
        PacketDecoder(AlacPacketDecoder codec) {
            super(new DecoderInputBuffer[4], new SimpleDecoderOutputBuffer[4]);
            this.codec = codec;
            setInitialInputBufferSize(32768);
        }
        @Override public String getName() { return "StillALAC"; }
        @Override protected DecoderInputBuffer createInputBuffer() {
            return new DecoderInputBuffer(DecoderInputBuffer.BUFFER_REPLACEMENT_MODE_NORMAL);
        }
        @Override protected SimpleDecoderOutputBuffer createOutputBuffer() {
            return new SimpleDecoderOutputBuffer(this::releaseOutputBuffer);
        }
        @Override protected DecodeError createUnexpectedDecodeException(Throwable error) { return new DecodeError(error); }
        @Override protected DecodeError decode(DecoderInputBuffer input, SimpleDecoderOutputBuffer output, boolean reset) {
            try {
                ByteBuffer data = input.data;
                if (data == null || data.remaining() > 1024 * 1024) throw new IllegalArgumentException("Invalid ALAC packet");
                byte[] packet = new byte[data.remaining()];
                data.get(packet);
                byte[] pcm = codec.decode(packet);
                output.init(input.timeUs, pcm.length).put(pcm).flip();
                return null;
            } catch (RuntimeException error) { return new DecodeError(error); }
        }
    }
}
