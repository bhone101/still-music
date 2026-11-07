package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test

class LibraryBrowsingTest {
    private fun song(id: String, title: String, artist: String = "Artist", duration: Long = 100) = Song(id, title, artist, "Album", "", duration, "flac")
    @Test fun stableSortingAndReversePreserveAllSongs() {
        val songs = listOf(song("c", "Same"), song("b", "Alpha"), song("a", "same"))
        assertEquals(listOf("b", "a", "c"), sortedSongs(songs, SongSort.Title, false).map { it.id })
        assertEquals(listOf("c", "a", "b"), sortedSongs(songs, SongSort.Title, true).map { it.id })
    }
    @Test fun durationAndModifiedSortNumerically() {
        val songs = listOf(song("a", "A", duration = 1000).copy(modified = 5), song("b", "B", duration = 90).copy(modified = 15))
        assertEquals("b", sortedSongs(songs, SongSort.Duration, false).first().id)
        assertEquals("b", sortedSongs(songs, SongSort.RecentlyModified, false).first().id)
    }
    @Test fun browserPaginationHandlesOverflowAndInvalidRequests() {
        assertEquals(listOf(3, 4), pageItems((0..4).toList(), 1, 3))
        assertEquals(emptyList<Int>(), pageItems(listOf(1), Int.MAX_VALUE, Int.MAX_VALUE))
        assertEquals(emptyList<Int>(), pageItems(listOf(1), -1, 3))
        assertEquals(emptyList<Int>(), pageItems(listOf(1), 0, 0))
    }
    @Test fun tenThousandSongsKeepStableIdentityAndOrder() {
        val songs = (10_000 downTo 1).map { song("id:$it", "Song ${it.toString().padStart(5, '0')}") }
        val start = System.nanoTime()
        val result = sortedSongs(songs, SongSort.Title, false)
        println("10,000-song host sort: ${(System.nanoTime() - start) / 1_000_000} ms (not a phone benchmark)")
        assertEquals("id:1", result.first().id)
        assertEquals("id:10000", result.last().id)
        assertEquals(10_000, result.map { it.id }.toSet().size)
    }
}
