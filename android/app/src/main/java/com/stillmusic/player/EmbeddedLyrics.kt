package com.stillmusic.player

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Read only small metadata ranges, never copy an audio file into memory. */
object EmbeddedLyrics {
    fun read(length: Long, reader: (Long, Int) -> ByteArray): String? {
        var budget = 4 * 1024 * 1024
        fun bytes(at: Long, count: Int): ByteArray {
            require(at >= 0 && count >= 0 && count <= budget && at <= length && count <= length - at)
            budget -= count
            return reader(at,count).also { require(it.size == count) }
        }
        if(length < 12) return null
        val header = bytes(0,12)
        if(header.copyOfRange(0,4).toString(Charsets.US_ASCII) == "fLaC") {
            var offset = 4L
            repeat(256) {
                val block = bytes(offset,4)
                val size = ((block[1].toInt() and 255) shl 16) or ((block[2].toInt() and 255) shl 8) or (block[3].toInt() and 255)
                if(block[0].toInt() and 127 == 4) {
                    val b = ByteBuffer.wrap(bytes(offset+4,size)).order(ByteOrder.LITTLE_ENDIAN)
                    val vendor = b.int; require(vendor >= 0 && vendor <= b.remaining()); b.position(b.position()+vendor)
                    val count = b.int; require(count in 0..100_000)
                    repeat(count) {
                        val n = b.int; require(n >= 0 && n <= b.remaining())
                        val text = ByteArray(n).also { b.get(it) }.toString(Charsets.UTF_8)
                        if(text.substringBefore('=').uppercase(java.util.Locale.ROOT) in setOf("LYRICS","UNSYNCEDLYRICS","SYNCEDLYRICS")) return text.substringAfter('=',"").takeIf { it.isNotBlank() }
                    }
                }
                offset += size + 4
                if(block[0].toInt() and 128 != 0) return null
            }
            return null
        }
        if(header.copyOfRange(0,3).toString(Charsets.US_ASCII) == "ID3") {
            val version = header[3].toInt()
            if(version !in 3..4 || header[5].toInt() and 0xC0 != 0) return null
            val size = syncSafe(header,6)
            val end = minOf(length,10L+size)
            var offset = 10L
            repeat(10_000) {
                if(offset+10 > end) return null
                val frame = bytes(offset,10)
                val id = frame.copyOfRange(0,4).toString(Charsets.US_ASCII)
                val n = if(version == 4) syncSafe(frame,4) else ByteBuffer.wrap(frame,4,4).int
                if(n <= 0 || offset+10+n > end) return null
                if(id == "USLT" && frame[8].toInt() == 0 && frame[9].toInt() == 0) return unsynced(bytes(offset+10,n))
                offset += 10+n
            }
            return null
        }
        // ISO BMFF: walk only the metadata containers; skip mdat without reading it.
        var atoms = 0
        fun visit(start: Long, end: Long, depth: Int): String? {
            if(depth > 8) return null
            var offset = start
            while(offset+8 <= end && atoms++ < 10_000) {
                val atom = bytes(offset,8)
                var size = ByteBuffer.wrap(atom,0,4).int.toLong() and 0xFFFFFFFFL
                var head = 8
                if(size == 1L) { size = ByteBuffer.wrap(bytes(offset+8,8)).long; head = 16 }
                if(size == 0L) size = end-offset
                if(size < head || size > end-offset) return null
                val type = atom.copyOfRange(4,8).toString(Charsets.ISO_8859_1)
                if(type == "©lyr") {
                    var p = offset+head
                    while(p+16 <= offset+size) {
                        val data = bytes(p,16)
                        val n = ByteBuffer.wrap(data,0,4).int.toLong() and 0xFFFFFFFFL
                        if(n < 16 || n > offset+size-p) break
                        if(data.copyOfRange(4,8).toString(Charsets.US_ASCII) == "data") {
                            val kind = ByteBuffer.wrap(data,8,4).int and 0xFFFFFF
                            val charset = if(kind == 2) Charsets.UTF_16BE else Charsets.UTF_8
                            return bytes(p+16,(n-16).toInt()).toString(charset).trim('\u0000').takeIf { it.isNotBlank() }
                        }
                        p += n
                    }
                }
                if(type in setOf("moov","udta","meta","ilst")) {
                    val child = offset+head+if(type == "meta") 4 else 0
                    visit(child,offset+size,depth+1)?.let { return it }
                }
                offset += size
            }
            return null
        }
        return visit(0,length,0)
    }
    private fun syncSafe(bytes: ByteArray, start: Int): Int {
        var n = 0
        repeat(4) { val b = bytes[start+it].toInt() and 255; require(b < 128); n = (n shl 7) or b }
        return n
    }
    private fun unsynced(data: ByteArray): String? {
        if(data.size < 5) return null
        val encoding = data[0].toInt()
        val wide = encoding == 1 || encoding == 2
        var i = 4
        while(i < data.size) {
            if(data[i] == 0.toByte() && (!wide || (i+1 < data.size && data[i+1] == 0.toByte()))) {
                i += if(wide) 2 else 1
                val charset = when(encoding) { 0 -> Charsets.ISO_8859_1; 1 -> Charsets.UTF_16; 2 -> Charsets.UTF_16BE; 3 -> Charsets.UTF_8; else -> return null }
                return data.copyOfRange(i,data.size).toString(charset).trim('\u0000','\uFEFF').takeIf { it.isNotBlank() }
            }
            i += if(wide) 2 else 1
        }
        return null
    }
}
