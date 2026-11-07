package com.stillmusic.player

import java.util.Locale

/** Stable document URIs identify tracks; list positions never identify a song. */
data class Song(
    val id: String, val title: String, val artist: String, val album: String,
    val albumArtist: String, val duration: Long, val format: String,
    val sampleRate: Int = 0, val bits: Int = 0, val root: String = "",
    val size: Long = 0, val modified: Long = 0, val lyricUri: String? = null,
    val folder: String = "", val genre: String = ""
) {
    val albumKey: String get() = "$album\u001f${albumArtist.ifBlank { artist }}"
    val quality: String get() = buildList {
        add(format.uppercase(Locale.ROOT))
        if (bits > 0) add("$bits-bit")
        if (sampleRate > 0) add("${sampleRate / 1000.0} kHz")
    }.joinToString(" · ")
}
data class Playlist(val id: String, val name: String, val songs: List<String>)
data class Library(val songs: List<Song> = emptyList(), val favorites: Set<String> = emptySet(), val playlists: List<Playlist> = emptyList())
data class LyricLine(val timeMs: Long, val text: String)
data class Lyrics(val lines: List<LyricLine>, val synced: Boolean)
enum class PlayMode { Normal, Shuffle;
    fun next() = if (this == Normal) Shuffle else Normal
    val label: String get() = if (this == Shuffle) "Shuffle on" else "Shuffle off"
}
fun durationText(ms: Long): String {
    val seconds = ms.coerceAtLeast(0) / 1000
    return "%d:%02d".format(Locale.ROOT, seconds / 60, seconds % 60)
}
object LyricParser {
    private val stamp = Regex("\\[(\\d+):([0-5]\\d)(?:[.:](\\d{1,3}))?]")
    private val offset = Regex("\\[offset:([+-]?\\d+)]", RegexOption.IGNORE_CASE)
    private val tag = Regex("^\\[(ar|al|ti|by|re|ve|length|offset):.*]$", RegexOption.IGNORE_CASE)
    fun parse(raw: String): Lyrics {
        val shift = offset.find(raw)?.groupValues?.get(1)?.toLongOrNull() ?: 0
        val timed = mutableListOf<LyricLine>()
        raw.lineSequence().forEach { line ->
            val matches = stamp.findAll(line).toList()
            val text = line.substring(matches.lastOrNull()?.range?.last?.plus(1) ?: 0).trim()
            matches.forEach { m ->
                val minutes = m.groupValues[1].toLongOrNull() ?: return@forEach
                if (minutes > 100_000) return@forEach
                val fraction = m.groupValues[3].padEnd(3, '0').take(3).toLongOrNull() ?: 0
                timed += LyricLine((minutes * 60_000 + m.groupValues[2].toLong() * 1000 + fraction + shift.coerceIn(-86_400_000, 86_400_000)).coerceAtLeast(0), text)
            }
        }
        if (timed.isNotEmpty()) return Lyrics(timed.sortedBy { it.timeMs }, true)
        return Lyrics(raw.lineSequence().map { it.trim() }.filter { it.isNotEmpty() && !tag.matches(it) }.map { LyricLine(0, it) }.toList(), false)
    }
    fun activeIndex(lines: List<LyricLine>, position: Long): Int {
        var low = 0; var high = lines.size
        while (low < high) { val mid = (low + high) / 2; if (lines[mid].timeMs <= position) low = mid + 1 else high = mid }
        return low - 1
    }
}

fun Library.withoutSong(id: String) = copy(songs = songs.filterNot { it.id == id }, favorites = favorites - id,
    playlists = playlists.map { it.copy(songs = it.songs.filterNot { songId -> songId == id }) })
fun timerMinutes(text: String): Int? = text.toIntOrNull()?.takeIf { it in 1..1440 }

internal fun <T> movedQueue(items: List<T>, from: Int, to: Int): List<T> {
    if(from !in items.indices || to !in items.indices) return items
    return items.toMutableList().apply { add(to, removeAt(from)) }
}

/** Insert by playback order, which can differ from physical indices in shuffle mode. */
internal fun queueWithAddition(order: List<Int>, current: Int, added: Int, next: Boolean): List<Int> = order.toMutableList().apply {
    val currentPosition = indexOf(current)
    add(if(next && currentPosition >= 0) currentPosition + 1 else size, added)
}

/** Commands that preserve selection order even when each Play next inserts at one position. */
internal fun <T> batchQueueCommands(songs: List<T>, next: Boolean, emptyQueue: Boolean): List<Pair<T, Boolean>> = when {
    !next -> songs.map { it to false }
    emptyQueue -> songs.take(1).map { it to false } + songs.drop(1).reversed().map { it to true }
    else -> songs.reversed().map { it to true }
}
