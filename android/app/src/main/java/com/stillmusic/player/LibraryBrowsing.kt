package com.stillmusic.player

import java.util.Locale

enum class SongSort(val label: String) {
    Title("Title"), Artist("Artist"), Album("Album"), Duration("Duration"), RecentlyModified("Recently modified")
}
internal fun sortedSongs(songs: List<Song>, sort: SongSort, descending: Boolean): List<Song> {
    val comparator = when (sort) {
        SongSort.Title -> compareBy<Song> { it.title.lowercase(Locale.ROOT) }
        SongSort.Artist -> compareBy<Song> { it.artist.lowercase(Locale.ROOT) }.thenBy { it.album.lowercase(Locale.ROOT) }
        SongSort.Album -> compareBy<Song> { it.album.lowercase(Locale.ROOT) }.thenBy { it.albumArtist.lowercase(Locale.ROOT) }
        SongSort.Duration -> compareBy<Song> { it.duration }
        SongSort.RecentlyModified -> compareByDescending<Song> { it.modified }
    }.thenBy { it.title.lowercase(Locale.ROOT) }.thenBy { it.id }
    return songs.sortedWith(if (descending) comparator.reversed() else comparator)
}
internal val Song.folderKey: String get() = "$root\u001f$folder"
internal val Song.folderLabel: String get() = folder.substringAfter(':').ifBlank { android.net.Uri.decode(root).substringAfterLast('/') }.ifBlank { "Unknown folder" }
internal val Song.genreLabel: String get() = genre.ifBlank { "Unknown genre" }
