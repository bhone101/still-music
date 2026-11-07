package com.stillmusic.player

import android.content.Context
import android.os.Bundle
import android.util.AtomicFile
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Physical queue indices and shuffle order are saved separately, including duplicate songs. */
internal data class SavedTrack(val id: String, val title: String, val artist: String, val album: String, val key: String) {
    fun mediaItem(): MediaItem = MediaItem.Builder().setMediaId(id).setUri(id).setMediaMetadata(
        MediaMetadata.Builder().setTitle(title).setArtist(artist).setAlbumTitle(album)
            .setIsPlayable(true).setIsBrowsable(false)
            .setExtras(Bundle().apply { putString("queueKey", key) }).build()).build()
}
internal data class PlaybackSnapshot(val tracks: List<SavedTrack>, val index: Int, val position: Long, val shuffle: Boolean, val order: List<Int>)
internal class PlaybackSnapshotStore(context: Context) {
    private val file = AtomicFile(File(context.filesDir, "playback-session.json"))
    fun read(): PlaybackSnapshot? = try {
        val root = file.openRead().bufferedReader().use { JSONObject(it.readText()) }
        val entries = root.getJSONArray("tracks")
        val tracks = (0 until entries.length()).map { i -> entries.getJSONObject(i).let {
            SavedTrack(it.getString("id"), it.optString("title"), it.optString("artist"), it.optString("album"), it.getString("key"))
        } }
        require(tracks.all { android.net.Uri.parse(it.id).scheme == "content" })
        val order = root.getJSONArray("order").let { a -> (0 until a.length()).map { a.getInt(it) } }
        require(order.sorted() == tracks.indices.toList())
        PlaybackSnapshot(tracks, root.optInt("index").coerceIn(0, (tracks.size - 1).coerceAtLeast(0)), root.optLong("position").coerceAtLeast(0), root.optBoolean("shuffle"), order)
    } catch (_: Exception) { null }
    fun write(snapshot: PlaybackSnapshot) {
        val json = JSONObject().put("tracks", JSONArray(snapshot.tracks.map {
            JSONObject().put("id", it.id).put("title", it.title).put("artist", it.artist).put("album", it.album).put("key", it.key)
        })).put("index", snapshot.index).put("position", snapshot.position).put("shuffle", snapshot.shuffle).put("order", JSONArray(snapshot.order))
        val out = file.startWrite()
        try { out.write(json.toString().toByteArray()); file.finishWrite(out) }
        catch (e: Exception) { file.failWrite(out); throw e }
    }
}
