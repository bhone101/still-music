package com.stillmusic.player

import java.nio.ByteBuffer

/** Bounded, codec-independent ISO BMFF metadata reader. Audio payloads are skipped. */
internal data class Mp4Tags(val duration: Long = 0, val title: String = "", val artist: String = "", val album: String = "", val albumArtist: String = "")
internal object Mp4Metadata {
    fun read(length: Long, reader: (Long, Int) -> ByteArray): Mp4Tags {
        var budget = 2 * 1024 * 1024
        var atoms = 0
        var movieDuration = 0L
        var audioDuration = 0L
        val tags = mutableMapOf<String, String>()
        fun bytes(at: Long, count: Int): ByteArray {
            require(at >= 0 && count >= 0 && count <= budget && at <= length && count <= length - at)
            budget -= count
            return reader(at, count).also { require(it.size == count) }
        }
        fun duration(at: Long, size: Long): Long {
            if(size < 20) return 0
            val version = bytes(at, 1)[0].toInt()
            val offset = when(version) { 0 -> 12; 1 -> 20; else -> return 0 }
            val count = if(version == 0) 8 else 12
            if(offset + count > size) return 0
            val b = ByteBuffer.wrap(bytes(at+offset, count))
            val scale = b.int.toLong() and 0xffffffffL
            val ticks = if(version == 0) (b.int.toLong() and 0xffffffffL).takeUnless { it == 0xffffffffL } ?: 0 else b.long
            if(scale <= 0 || ticks <= 0) return 0
            val ms = ticks.toDouble() / scale * 1000
            return if(ms.isFinite() && ms < Long.MAX_VALUE) ms.toLong() else 0
        }
        fun visit(start: Long, end: Long, depth: Int, tag: String? = null) {
            require(depth <= 10)
            var at = start
            var mediaDuration = 0L
            var isAudio = false
            while(at <= end - 8) {
                require(++atoms <= 10000)
                val header = bytes(at, 8)
                var size = ByteBuffer.wrap(header).int.toLong() and 0xffffffffL
                var head = 8
                if(size == 1L) { size = ByteBuffer.wrap(bytes(at+8,8)).long; head = 16 }
                if(size == 0L) size = end-at
                require(size >= head && size <= end-at)
                val type = header.copyOfRange(4,8).toString(Charsets.ISO_8859_1)
                val payload = at + head
                val remaining = size - head
                when {
                    type == "mvhd" -> movieDuration = duration(payload, remaining)
                    type == "mdhd" -> mediaDuration = duration(payload, remaining)
                    type == "hdlr" && remaining >= 12 -> isAudio = bytes(payload+8,4).toString(Charsets.US_ASCII) == "soun"
                    type == "data" && tag != null && remaining in 8..65536 -> {
                        val data = bytes(payload, remaining.toInt())
                        val kind = ByteBuffer.wrap(data).int and 0xffffff
                        if(kind == 1 || kind == 2) tags[tag] = data.copyOfRange(8,data.size).toString(if(kind == 2) Charsets.UTF_16BE else Charsets.UTF_8).trim('\u0000', '\uFEFF', ' ')
                    }
                    type in setOf("©nam", "©ART", "©alb", "aART") -> visit(payload, at+size, depth+1, type)
                    type in setOf("moov", "trak", "mdia", "udta", "meta", "ilst") -> visit(payload + if(type == "meta") 4 else 0, at+size, depth+1)
                }
                at += size
            }
            if(isAudio && mediaDuration > 0) audioDuration = maxOf(audioDuration, mediaDuration)
        }
        if(length < 8) return Mp4Tags()
        visit(0,length,0)
        return Mp4Tags(movieDuration.takeIf { it > 0 } ?: audioDuration, tags["©nam"].orEmpty(), tags["©ART"].orEmpty(), tags["©alb"].orEmpty(), tags["aART"].orEmpty())
    }
}
