package com.stillmusic.player

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL

internal class LyricsLookupException(message: String) : java.io.IOException(message)

class LyricsRepository(private val context: Context) {
    suspend fun local(song: Song): Lyrics = withContext(Dispatchers.IO) {
        if (song.lyricUri == null) {
            val descriptor = context.contentResolver.openFileDescriptor(Uri.parse(song.id), "r") ?: return@withContext Lyrics(emptyList(), false)
            val text = android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { stream ->
                    val channel = stream.channel
                    EmbeddedLyrics.read(channel.size()) { position, count ->
                        val buffer = java.nio.ByteBuffer.allocate(count)
                        channel.position(position)
                        while (buffer.hasRemaining()) { if (channel.read(buffer) <= 0) throw java.io.EOFException() }
                        buffer.array()
                    }
            }
            return@withContext LyricParser.parse(text.orEmpty())
        }
        context.contentResolver.openInputStream(Uri.parse(song.lyricUri))?.use { stream ->
            val bytes = stream.readBytesBounded()
            val text = when {
                bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte() -> bytes.toString(Charsets.UTF_16LE).removePrefix("\uFEFF")
                bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte() -> bytes.toString(Charsets.UTF_16BE).removePrefix("\uFEFF")
                else -> bytes.toString(Charsets.UTF_8).removePrefix("\uFEFF")
            }
            LyricParser.parse(text)
        } ?: Lyrics(emptyList(), false)
    }
    private fun cacheFile(song: Song): java.io.File {
        val key = java.security.MessageDigest.getInstance("SHA-256").digest("${song.id}:${song.modified}:${song.size}".toByteArray()).joinToString("") { "%02x".format(it) }
        return java.io.File(context.filesDir, "lyrics-v2/$key.json")
    }
    suspend fun cached(song: Song): Lyrics? = withContext(Dispatchers.IO) {
        try {
            val json = org.json.JSONObject(android.util.AtomicFile(cacheFile(song)).openRead().use { it.readBytesBounded().toString(Charsets.UTF_8) })
            val lines = json.getJSONArray("lines")
            Lyrics((0 until lines.length()).map { val line = lines.getJSONObject(it); LyricLine(line.getLong("time"), line.getString("text")) }, json.getBoolean("synced")).takeIf { it.lines.isNotEmpty() }
        } catch (_: Exception) { null }
    }
    internal fun save(song: Song, lyrics: Lyrics) {
        if(lyrics.lines.isEmpty()) return
        val file = cacheFile(song); file.parentFile?.mkdirs()
        val atomic = android.util.AtomicFile(file)
        val stream = atomic.startWrite()
        try {
            val lines = JSONArray()
            lyrics.lines.forEach { lines.put(org.json.JSONObject().put("time", it.timeMs).put("text", it.text)) }
            stream.write(org.json.JSONObject().put("synced", lyrics.synced).put("lines", lines).toString().toByteArray())
            atomic.finishWrite(stream)
        } catch(e: Exception) { atomic.failWrite(stream); throw e }
    }
    suspend fun online(song: Song): Lyrics? = withContext(Dispatchers.IO) {
        cached(song)?.let { return@withContext it }
        lookupLock.withLock {
            cached(song)?.let { return@withLock it }
            val artist = searchArtist(song)
            val title = cleanTitle(song.title)
            val queries = listOf(
                listOf("track_name" to song.title, "artist_name" to artist),
                listOf("track_name" to title, "artist_name" to primaryArtist(artist)),
                listOf("q" to "$title ${primaryArtist(artist)}".trim())
            ).map { pairs -> pairs.filter { it.second.isNotBlank() } }.distinct()
            for(query in queries) {
                val now = android.os.SystemClock.elapsedRealtime()
                if(now < retryAfter) throw LyricsLookupException("Lyrics service is busy. Please try again later.")
                kotlinx.coroutines.delay((nextRequest - now).coerceAtLeast(0))
                val uri = Uri.parse("https://lrclib.net/api/search").buildUpon()
                query.forEach { (key,value) -> uri.appendQueryParameter(key,value) }
                val connection = URL(uri.build().toString()).openConnection() as HttpURLConnection
                try {
                    connection.connectTimeout = 10000; connection.readTimeout = 15000
                    connection.instanceFollowRedirects = false
                    connection.setRequestProperty("User-Agent", "StillMusic/0.5.4 (https://github.com/bhone101/still-music)")
                    val code = connection.responseCode
                    if(code == 429) {
                        val seconds = connection.getHeaderField("Retry-After")?.toLongOrNull()?.coerceIn(1,86400) ?: 60
                        retryAfter = android.os.SystemClock.elapsedRealtime() + seconds * 1000
                        throw LyricsLookupException("Lyrics service is busy. Please try again later.")
                    }
                    if(code != 200) throw LyricsLookupException("Lyrics service unavailable ($code). Try again later.")
                    val array = connection.inputStream.use { JSONArray(it.readBytesBounded().toString(Charsets.UTF_8)) }
                    selectLyrics(array, song)?.let { found -> runCatching { save(song, found) }; return@withLock found }
                } finally { connection.disconnect(); nextRequest = android.os.SystemClock.elapsedRealtime() + 300 }
            }
            null
        }
    }
    companion object {
        private val lookupLock = kotlinx.coroutines.sync.Mutex()
        private var nextRequest = 0L
        private var retryAfter = 0L
    }
    private fun java.io.InputStream.readBytesBounded(): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) { val count = read(buffer); if (count < 0) break; require(out.size() + count <= 1_048_576) { "Lyrics file is too large" }; out.write(buffer, 0, count) }
        return out.toByteArray()
    }
}

internal fun normalized(value: String): String = java.text.Normalizer.normalize(value, java.text.Normalizer.Form.NFKD)
    .replace(Regex("(?<=\\p{IsLatin})\\p{M}+"), "").lowercase(java.util.Locale.ROOT).replace("’", "").replace("'", "")
    .replace(Regex("[^\\p{L}\\p{N}\\p{M}]+"), " ").trim()
internal fun cleanTitle(value: String): String = value
    .replace(Regex("(?i)\\s*[\\[(][^\\])]*remaster[^\\])]*[\\])]"), "")
    .replace(Regex("(?i)\\s*[-–—]\\s*(?:\\d{4}\\s*)?remaster(?:ed)?(?:\\s+\\d{4})?\\s*$"), "").trim()
internal fun primaryArtist(value: String): String = value.split(Regex("(?i)\\s+(?:feat\\.?|ft\\.?|featuring)\\s+|\\s*[;&]\\s*"), limit = 2).first().trim()
internal fun searchArtist(song: Song): String = song.artist.takeUnless { it.isBlank() || it.equals("Unknown artist", true) }
    ?: song.albumArtist.takeUnless { it.isBlank() || it.equals("Various artists", true) }.orEmpty()

internal fun selectLyrics(array: JSONArray, song: Song): Lyrics? {
    val artist = searchArtist(song)
    val title = normalized(cleanTitle(song.title))
    if(title.isBlank()) return null
    val candidates = (0 until array.length()).map { array.getJSONObject(it) }.filter {
        normalized(cleanTitle(it.optString("trackName"))) == title &&
            (artist.isBlank() || normalized(it.optString("artistName")) == normalized(artist) ||
                normalized(primaryArtist(it.optString("artistName"))) == normalized(primaryArtist(artist)))
    }
    // Title-only matches must have a measured duration and an unambiguous artist.
    val matches = candidates.filter {
        val duration = it.optDouble("duration", -1.0) * 1000
        if(song.duration <= 0) artist.isNotBlank()
        else duration > 0 && kotlin.math.abs(duration - song.duration) <= if(artist.isBlank()) 3000 else 15000
    }
    if(artist.isBlank() && matches.map { normalized(it.optString("artistName")) }.distinct().size != 1) return null
    return matches.sortedWith(compareByDescending<org.json.JSONObject> { normalized(it.optString("albumName")) == normalized(song.album) }
        .thenBy { if(song.duration > 0) kotlin.math.abs(it.optDouble("duration", -1.0)*1000-song.duration) else 0.0 }
        .thenByDescending { !it.isNull("syncedLyrics") && it.optString("syncedLyrics").isNotBlank() })
        .firstNotNullOfOrNull { record ->
            val closeTiming = song.duration <= 0 || kotlin.math.abs(record.optDouble("duration", -1.0)*1000-song.duration) <= 5000
            val synced = if(record.isNull("syncedLyrics")) null else LyricParser.parse(record.optString("syncedLyrics")).takeIf { it.lines.isNotEmpty() }
            val plain = if(record.isNull("plainLyrics")) null else LyricParser.parse(record.optString("plainLyrics")).takeIf { it.lines.isNotEmpty() }
            if(closeTiming) synced ?: plain else plain ?: synced?.let { Lyrics(it.lines.map { line -> line.copy(timeMs = 0) }, false) }
        }
}

internal suspend fun resolveLyrics(search: Boolean, local: suspend () -> Lyrics, cached: suspend () -> Lyrics?, online: suspend () -> Lyrics?): Lyrics {
    val existing = try { local() } catch(e: Exception) {
        if(e is kotlinx.coroutines.CancellationException) throw e
        Lyrics(emptyList(), false)
    }
    if(existing.lines.isNotEmpty()) return existing
    cached()?.takeIf { it.lines.isNotEmpty() }?.let { return it }
    return if(search) online() ?: existing else existing
}
