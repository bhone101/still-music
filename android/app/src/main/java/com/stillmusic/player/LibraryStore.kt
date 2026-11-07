package com.stillmusic.player

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.util.AtomicFile
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

class LibraryStore(private val context: Context) {
    private val file = AtomicFile(File(context.filesDir, "library-v2.json"))
    fun read(): Library {
        if (!file.baseFile.exists() && !java.io.File(file.baseFile.path + ".bak").exists()) return Library()
        val json = file.openRead().bufferedReader().use { JSONObject(it.readText()) }
        val songs = json.optJSONArray("songs") ?: JSONArray()
        val lists = json.optJSONArray("playlists") ?: JSONArray()
        return Library((0 until songs.length()).map { i -> songs.getJSONObject(i).let { o ->
            Song(o.getString("id"), o.getString("title"), o.getString("artist"), o.getString("album"),
                o.optString("albumArtist"), o.optLong("duration"), o.optString("format"), o.optInt("sampleRate"), o.optInt("bits"),
                o.optString("root"), o.optLong("size"), o.optLong("modified"), o.optString("lyricUri").ifBlank { null }, o.optString("folder"), o.optString("genre"))
        } }, json.optJSONArray("favorites").strings().toSet(), (0 until lists.length()).map { i -> lists.getJSONObject(i).let {
            Playlist(it.getString("id"), it.getString("name"), it.optJSONArray("songs").strings())
        } })
    }
    fun write(library: Library) {
        val json = JSONObject().put("songs", JSONArray(library.songs.map { s ->
            JSONObject().put("id", s.id).put("title", s.title).put("artist", s.artist).put("album", s.album)
                .put("albumArtist", s.albumArtist).put("duration", s.duration).put("format", s.format)
                .put("sampleRate", s.sampleRate).put("bits", s.bits).put("root", s.root)
                .put("size", s.size).put("modified", s.modified).put("lyricUri", s.lyricUri ?: "").put("folder", s.folder).put("genre", s.genre)
        })).put("favorites", JSONArray(library.favorites.toList())).put("playlists", JSONArray(library.playlists.map {
            JSONObject().put("id", it.id).put("name", it.name).put("songs", JSONArray(it.songs))
        }))
        val stream = file.startWrite()
        try { stream.write(json.toString().toByteArray()); file.finishWrite(stream) }
        catch (e: Exception) { file.failWrite(stream); throw e }
    }
    private fun JSONArray?.strings(): List<String> = if (this == null) emptyList() else (0 until length()).map { getString(it) }

    internal fun repairMp4(song: Song): Song {
        if(song.format.lowercase(Locale.ROOT) !in setOf("m4a", "m4b")) return song
        return try {
            val descriptor = context.contentResolver.openFileDescriptor(Uri.parse(song.id), "r") ?: return song
            val tags = android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { stream ->
                val channel = stream.channel
                Mp4Metadata.read(channel.size()) { at, count ->
                    val buffer = java.nio.ByteBuffer.allocate(count)
                    channel.position(at)
                    while(buffer.hasRemaining()) { if(channel.read(buffer) <= 0) throw java.io.EOFException() }
                    buffer.array()
                }
            }
            song.copy(duration = song.duration.takeIf { it > 0 } ?: tags.duration,
                title = tags.title.ifBlank { song.title }, artist = tags.artist.ifBlank { song.artist },
                album = tags.album.ifBlank { song.album }, albumArtist = tags.albumArtist.ifBlank { song.albumArtist })
        } catch (_: Exception) { song }
    }
    private data class Entry(val id: String, val name: String, val mime: String, val size: Long, val modified: Long)
    suspend fun scan(root: Uri, existing: List<Song>): List<Song> {
        val resolver = context.contentResolver
        val old = existing.associateBy { it.id }
        val pending = ArrayDeque<String>().apply { add(DocumentsContract.getTreeDocumentId(root)) }
        val visited = hashSetOf<String>()
        val result = linkedMapOf<String, Song>()
        val extensions = setOf("flac", "mp3", "m4a", "m4b", "aac", "adts", "wav", "wave", "ogg", "oga", "opus", "aiff", "aif", "aifc")
        while (pending.isNotEmpty()) {
            currentCoroutineContext().ensureActive()
            val parent = pending.removeFirst()
            if (!visited.add(parent)) continue
            val uri = DocumentsContract.buildChildDocumentsUriUsingTree(root, parent)
            val entries = mutableListOf<Entry>()
            resolver.query(uri, arrayOf("document_id", "_display_name", "mime_type", "_size", "last_modified"), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) entries += Entry(cursor.getString(0), cursor.getString(1) ?: "", cursor.getString(2) ?: "", cursor.getLong(3), cursor.getLong(4))
            } ?: error("Folder is unavailable")
            val siblings = entries.associateBy { it.name.lowercase(Locale.ROOT) }
            for (e in entries) {
                currentCoroutineContext().ensureActive()
                if (e.mime == DocumentsContract.Document.MIME_TYPE_DIR) { pending.add(e.id); continue }
                val ext = e.name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                if (ext !in extensions) continue
                val songUri = DocumentsContract.buildDocumentUriUsingTree(root, e.id)
                val stem = e.name.substringBeforeLast('.').lowercase(Locale.ROOT)
                val sidecar = siblings["$stem.lrc"] ?: siblings["$stem.txt"]
                val lyricUri = sidecar?.let { DocumentsContract.buildDocumentUriUsingTree(root, it.id).toString() }
                val cached = old[songUri.toString()]
                if (cached != null && cached.folder.isNotBlank() && cached.duration > 0 && e.size > 0 && e.modified > 0 && cached.size == e.size && cached.modified == e.modified) {
                    result[songUri.toString()] = cached.copy(root = root.toString(), lyricUri = lyricUri)
                    continue
                }
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, songUri)
                    fun meta(key: Int) = retriever.extractMetadata(key).orEmpty()
                    result[songUri.toString()] = Song(songUri.toString(), meta(MediaMetadataRetriever.METADATA_KEY_TITLE).ifBlank { e.name.substringBeforeLast('.') },
                        meta(MediaMetadataRetriever.METADATA_KEY_ARTIST).ifBlank { "Unknown artist" }, meta(MediaMetadataRetriever.METADATA_KEY_ALBUM).ifBlank { "Unknown album" }, meta(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST), meta(MediaMetadataRetriever.METADATA_KEY_DURATION).toLongOrNull() ?: 0,
                        ext, sampleRate = if (android.os.Build.VERSION.SDK_INT >= 31) meta(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE).toIntOrNull() ?: 0 else 0,
                        bits = if (android.os.Build.VERSION.SDK_INT >= 31) meta(MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE).toIntOrNull() ?: 0 else 0,
                        root = root.toString(), size = e.size, modified = e.modified, lyricUri = lyricUri, folder = parent, genre = meta(MediaMetadataRetriever.METADATA_KEY_GENRE))
                } catch (_: Exception) {
                    result[songUri.toString()] = Song(songUri.toString(), e.name.substringBeforeLast('.'), "Unknown artist", "Unknown album", "", 0, ext,
                        root = root.toString(), size = e.size, modified = e.modified, lyricUri = lyricUri, folder = parent)
                } finally { retriever.release() }
                result[songUri.toString()]?.let { result[songUri.toString()] = repairMp4(it) }
            }
        }
        // Prepare small persistent covers before publishing the newly scanned library.
        result.values.take(40).forEach { currentCoroutineContext().ensureActive(); Artwork.load(context, it) }
        return result.values.toList()
    }
}
