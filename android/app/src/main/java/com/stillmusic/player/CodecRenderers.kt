package com.stillmusic.player

import android.content.Context
import android.os.Handler
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal fun codecRenderers(context: Context): DefaultRenderersFactory = object : DefaultRenderersFactory(context) {
    override fun buildAudioRenderers(context: Context, extensionRendererMode: Int, mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean, audioSink: AudioSink, eventHandler: Handler,
        eventListener: AudioRendererEventListener, out: ArrayList<Renderer>) {
        val first = out.size
        super.buildAudioRenderers(context, extensionRendererMode, mediaCodecSelector, enableDecoderFallback, audioSink, eventHandler, eventListener, out)
        out.add(first, AlacAudioRenderer(eventHandler, eventListener, audioSink))
    }
}.setEnableAudioFloatOutput(false).setEnableDecoderFallback(true)
