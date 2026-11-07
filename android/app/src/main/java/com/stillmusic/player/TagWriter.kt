package com.stillmusic.player

import android.content.Context
import android.net.Uri
import java.io.*
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal data class TagChanges(val values: Map<String, String>) {
    fun apply(song: Song) = song.copy(title = values["TITLE"] ?: song.title, artist = values["ARTIST"] ?: song.artist,
        album = values["ALBUM"] ?: song.album, albumArtist = values["ALBUMARTIST"] ?: song.albumArtist, genre = values["GENRE"] ?: song.genre)
}

/** Bounded metadata rewriting. Unrecognized metadata and the encoded audio are copied unchanged. */
internal object TagWriter {
    private const val MAX_TAG = 16 * 1024 * 1024
    private val frames = mapOf("TITLE" to "TIT2", "ARTIST" to "TPE1", "ALBUM" to "TALB", "ALBUMARTIST" to "TPE2", "GENRE" to "TCON")
    fun rewrite(input: InputStream, output: OutputStream, format: String, changes: TagChanges) {
        require(changes.values.keys.all { it in frames }) { "Unsupported field" }
        require(changes.values.values.all { it.length <= 1000 }) { "Tag text is too long" }
        when (format.lowercase(java.util.Locale.ROOT)) { "mp3" -> mp3(input, output, changes); "flac" -> flac(input, output, changes); else -> error("Editing supports MP3 and FLAC files") }
    }
    private fun read(input: InputStream, count: Int): ByteArray {
        require(count in 0..MAX_TAG) { "Metadata is too large" }
        return ByteArray(count).also { DataInputStream(input).readFully(it) }
    }
    private fun sync(bytes: ByteArray): Int {
        require(bytes.size == 4 && bytes.all { it.toInt() and 128 == 0 }) { "Invalid ID3 size" }
        return bytes.fold(0) { value, byte -> (value shl 7) or byte.toInt() }
    }
    private fun syncBytes(size: Int) = byteArrayOf((size shr 21).toByte(), ((size shr 14) and 127).toByte(), ((size shr 7) and 127).toByte(), (size and 127).toByte())
    private fun mp3(source: InputStream, output: OutputStream, changes: TagChanges) {
        val input = PushbackInputStream(source, 10)
        val header = read(input, 10)
        var version = 3
        val result = ByteArrayOutputStream()
        if (String(header, 0, 3, Charsets.ISO_8859_1) == "ID3") {
            version = header[3].toInt()
            require(version == 3 || version == 4) { "Only ID3v2.3 and ID3v2.4 tags can be edited" }
            require(header[5].toInt() == 0) { "This ID3 tag uses unsupported flags; the file was kept" }
            val body = read(input, sync(header.copyOfRange(6, 10)))
            var offset = 0
            while (offset < body.size && body[offset] != 0.toByte()) {
                require(offset + 10 <= body.size) { "Truncated ID3 frame" }
                val id = String(body, offset, 4, Charsets.ISO_8859_1)
                require(id.matches(Regex("[A-Z0-9]{4}"))) { "Invalid ID3 frame" }
                val sizeBytes = body.copyOfRange(offset + 4, offset + 8)
                val size = if (version == 4) sync(sizeBytes) else ByteBuffer.wrap(sizeBytes).int
                require(size >= 0 && size <= body.size - offset - 10) { "Invalid ID3 frame size" }
                if (id !in changes.values.keys.mapNotNull { frames[it] }) result.write(body, offset, 10 + size)
                offset += 10 + size
            }
            require(body.drop(offset).all { it == 0.toByte() }) { "Unexpected ID3 padding data" }
        } else input.unread(header)
        changes.values.forEach { (key, value) ->
            val bytes = if (version == 4) byteArrayOf(3) + value.toByteArray(Charsets.UTF_8) else byteArrayOf(1) + value.toByteArray(Charsets.UTF_16)
            result.write(frames.getValue(key).toByteArray(Charsets.ISO_8859_1))
            result.write(if (version == 4) syncBytes(bytes.size) else ByteBuffer.allocate(4).putInt(bytes.size).array())
            result.write(byteArrayOf(0, 0)); result.write(bytes)
        }
        require(result.size() <= MAX_TAG)
        output.write("ID3".toByteArray()); output.write(byteArrayOf(version.toByte(), 0, 0)); output.write(syncBytes(result.size())); result.writeTo(output)
        input.copyTo(output)
    }
    private fun flac(input: InputStream, output: OutputStream, changes: TagChanges) {
        require(String(read(input, 4), Charsets.US_ASCII) == "fLaC") { "Invalid FLAC header" }
        val blocks = mutableListOf<Pair<Int, ByteArray>>()
        var total = 0
        do {
            val header = read(input, 4)
            val type = header[0].toInt() and 127
            val size = ((header[1].toInt() and 255) shl 16) or ((header[2].toInt() and 255) shl 8) or (header[3].toInt() and 255)
            total += size; require(total <= MAX_TAG) { "FLAC metadata is too large" }
            blocks += type to read(input, size)
            val last = header[0].toInt() and 128 != 0
        } while (!last)
        require(blocks.firstOrNull()?.first == 0 && blocks.first().second.size == 34) { "Invalid FLAC stream info" }
        require(blocks.count { it.first == 4 } <= 1) { "Duplicate FLAC comment blocks" }
        val existing = blocks.firstOrNull { it.first == 4 }?.second
        var vendor = "Still Music".toByteArray()
        val comments = mutableListOf<String>()
        if (existing != null) {
            val buffer = ByteBuffer.wrap(existing).order(ByteOrder.LITTLE_ENDIAN)
            fun field(): ByteArray { require(buffer.remaining() >= 4); val n = buffer.int; require(n >= 0 && n <= buffer.remaining()); return ByteArray(n).also { buffer.get(it) } }
            vendor = field(); require(buffer.remaining() >= 4)
            val count = buffer.int; require(count >= 0 && count <= buffer.remaining() / 4)
            repeat(count) { comments += String(field(), Charsets.UTF_8) }
            require(!buffer.hasRemaining()) { "Unexpected FLAC comment data" }
        }
        comments.removeAll { it.substringBefore('=').uppercase(java.util.Locale.ROOT) in changes.values }
        changes.values.forEach { (key, value) -> comments += "$key=$value" }
        val comment = ByteArrayOutputStream()
        fun number(n: Int) { comment.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(n).array()) }
        fun field(bytes: ByteArray) { number(bytes.size); comment.write(bytes) }
        field(vendor); number(comments.size); comments.forEach { field(it.toByteArray(Charsets.UTF_8)) }
        require(comment.size() <= 0xFFFFFF)
        val position = blocks.indexOfFirst { it.first == 4 }
        if (position >= 0) blocks[position] = 4 to comment.toByteArray() else blocks.add(4 to comment.toByteArray())
        output.write("fLaC".toByteArray())
        blocks.forEachIndexed { index, (type, bytes) ->
            output.write(byteArrayOf((type or if (index == blocks.lastIndex) 128 else 0).toByte(), (bytes.size shr 16).toByte(), (bytes.size shr 8).toByte(), bytes.size.toByte()))
            output.write(bytes)
        }
        input.copyTo(output)
    }
    private fun replaceDocument(context: Context, id: String, file: File) {
        val descriptor = context.contentResolver.openFileDescriptor(Uri.parse(id), "rw") ?: error("File is unavailable")
        android.os.ParcelFileDescriptor.AutoCloseOutputStream(descriptor).channel.use { channel ->
            channel.position(0) // Refuse non-seekable providers before changing the document.
            file.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                var count = input.read(buffer)
                while (count >= 0) {
                    if (count > 0) { val bytes = ByteBuffer.wrap(buffer, 0, count); while (bytes.hasRemaining()) channel.write(bytes) }
                    count = input.read(buffer)
                }
            }
            channel.truncate(file.length()); channel.force(true)
        }
    }
    fun recoveryCount(context: Context): Int = journals(context).size
    private fun journals(context: Context): List<File> = File(context.filesDir, "tag-transactions").listFiles()?.filter { it.extension == "txt" }.orEmpty()
    fun recover(context: Context): List<String> = journals(context).mapNotNull { journal ->
        val original = File(journal.path.removeSuffix(".txt"))
        try {
            val id = journal.useLines { it.first() }
            require(Uri.parse(id).scheme == "content" && original.isFile)
            replaceDocument(context, id, original)
            journal.delete(); original.delete()
            null
        } catch (e: Exception) { "${original.name}: ${e.message ?: "Storage unavailable"}" }
    }
    /** Stage and validate before touching the document. Roll back failures; retain original if rollback fails. */
    fun write(context: Context, song: Song, changes: TagChanges): Song {
        require(song.format.lowercase(java.util.Locale.ROOT) in setOf("mp3", "flac")) { "${song.format.uppercase(java.util.Locale.ROOT)} editing is not supported" }
        val directory = File(context.filesDir, "tag-transactions").apply { mkdirs() }
        require(journals(context).none { it.useLines { lines -> lines.firstOrNull() == song.id } }) { "Recover the interrupted edit in Settings first" }
        val original = File.createTempFile("original-", ".audio", directory)
        val edited = File.createTempFile("edited-", ".audio", directory)
        val journal = File(original.path + ".txt")
        var keepOriginal = false
        try {
            require(song.size <= 0 || directory.usableSpace > song.size * 2 + MAX_TAG) { "Not enough storage to safely edit this file" }
            context.contentResolver.openInputStream(Uri.parse(song.id))!!.use { input -> original.outputStream().use { input.copyTo(it); it.fd.sync() } }
            original.inputStream().use { input -> edited.outputStream().use { rewrite(input, it, song.format, changes) } }
            journal.outputStream().use { it.write("${song.id}\n${song.title}\n".toByteArray()); it.fd.sync() }
            commitTagEdit(original, edited, { replaceDocument(context, song.id, it) }) { keepOriginal = true }
            // Force the next scan to refresh size and modification metadata.
            return changes.apply(song).copy(size = 0, modified = 0)
        } finally {
            edited.delete()
            if (!keepOriginal) { original.delete(); journal.delete() }
        }
    }
}

/** Cancellation is checked between files, never in the middle of a commit/rollback. */
internal fun commitTagEdit(original: File, edited: File, replace: (File) -> Unit, retainOriginal: () -> Unit) {
    try { replace(edited) }
    catch (failure: Exception) {
        try { replace(original) }
        catch (_: Exception) {
            retainOriginal()
            throw IOException("Write and recovery failed. Original retained in app storage: ${original.name}. Do not uninstall Still.", failure)
        }
        throw IOException("Could not save; original file restored", failure)
    }
}
