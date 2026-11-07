package com.beatofthedrum.alacdecoder;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

/** Bounded packet adapter for Media3's 24-byte ALACSpecificConfig. */
public final class AlacPacketDecoder {
    public final int channels;
    public final int sampleRate;
    public final int bitDepth;
    private final int maxFrames;
    private final AlacFile decoder;
    private final int[] samples;

    public AlacPacketDecoder(byte[] config) {
        if (config.length != 24) throw new IllegalArgumentException("Invalid ALAC configuration");
        ByteBuffer info = ByteBuffer.wrap(config).order(ByteOrder.BIG_ENDIAN);
        maxFrames = info.getInt(0);
        bitDepth = config[5] & 255;
        channels = config[9] & 255;
        sampleRate = info.getInt(20);
        if (maxFrames <= 0 || maxFrames > 16384 || (bitDepth != 16 && bitDepth != 24)
                || channels < 1 || channels > 2 || sampleRate < 8000 || sampleRate > 384000
                || config[4] != 0 || (config[8] & 255) > 31) {
            throw new IllegalArgumentException("Unsupported ALAC configuration");
        }
        decoder = AlacFile.create(bitDepth, channels);
        int[] legacyConfig = new int[48];
        for (int i = 0; i < config.length; i++) legacyConfig[24 + i] = config[i] & 255;
        decoder.setAlacInfo(legacyConfig);
        // The upstream 24-bit decoder writes byte values into ints, plus one spare mono slot.
        samples = new int[maxFrames * channels * 3 + 6];
    }

    public byte[] decode(byte[] packet) {
        if (packet.length < 3 || packet.length > 1024 * 1024) throw new IllegalArgumentException("Invalid ALAC packet size");
        // The bit reader looks ahead up to three bytes at a packet boundary.
        byte[] padded = Arrays.copyOf(packet, packet.length + 3);
        int decodedBytes = decoder.decodeFrame(padded, samples, samples.length);
        int sourceBytes = bitDepth / 8;
        if (decodedBytes <= 0 || decodedBytes > maxFrames * channels * sourceBytes
                || decodedBytes % (channels * sourceBytes) != 0) {
            throw new IllegalArgumentException("Invalid ALAC output size");
        }
        int count = decodedBytes / sourceBytes;
        ByteBuffer pcm = ByteBuffer.allocate(count * 2).order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < count; i++) {
            // Match the app's established integer PCM output path, never reinterpret as float.
            int sample = bitDepth == 16 ? samples[i] : (samples[i * 3 + 1] & 255) | (samples[i * 3 + 2] << 8);
            pcm.putShort((short) sample);
        }
        return pcm.array();
    }
}
