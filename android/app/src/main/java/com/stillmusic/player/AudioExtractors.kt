package com.stillmusic.player

import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal fun audioExtractors(): Array<Extractor> =
    arrayOf(AiffExtractor(), *DefaultExtractorsFactory().createExtractors())
