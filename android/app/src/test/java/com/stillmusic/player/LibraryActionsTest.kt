package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test

class LibraryActionsTest {
    @Test fun batchQueueActionsKeepDisplayedOrder() {
        fun apply(initial: List<String>, next: Boolean): List<String> {
            val queue = initial.toMutableList()
            batchQueueCommands(listOf("a", "b", "c"), next, queue.isEmpty()).forEach { (song, insertNext) ->
                queue.add(if (insertNext && queue.isNotEmpty()) 1 else queue.size, song)
            }
            return queue
        }
        assertEquals(listOf("current", "a", "b", "c", "later"), apply(listOf("current", "later"), true))
        assertEquals(listOf("current", "later", "a", "b", "c"), apply(listOf("current", "later"), false))
        assertEquals(listOf("a", "b", "c"), apply(emptyList(), true))
        assertEquals(emptyList<Pair<String, Boolean>>(), batchQueueCommands(emptyList<String>(), true, true))
    }
    @Test fun deletingSongRemovesAllReferencesAndKeepsOtherFiles() {
        val one = Song("one", "One", "A", "B", "", 1, "flac")
        val two = one.copy(id = "two")
        val result = Library(listOf(one, two), setOf("one", "two"), listOf(Playlist("p", "List", listOf("one", "two", "one")))).withoutSong("one")
        assertEquals(listOf(two), result.songs)
        assertEquals(setOf("two"), result.favorites)
        assertEquals(listOf("two"), result.playlists.single().songs)
    }
    @Test fun queueMovesRespectVisibleOrderAndKeepEveryEntry() {
        val order = listOf(4, 0, 3, 1, 2)
        assertEquals(listOf(4, 3, 1, 0, 2), movedQueue(order, 1, 3))
        assertEquals(listOf(2, 4, 0, 3, 1), movedQueue(order, 4, 0))
        assertEquals(order, movedQueue(order, -1, 0))
        assertEquals(order, movedQueue(order, 2, 2))
    }
    @Test fun playNextInsertsAfterCurrentWithoutDroppingExistingSongs() {
        assertEquals(listOf(0, 1, 4, 2, 3), queueWithAddition(listOf(0, 1, 2, 3), 1, 4, true))
        assertEquals(listOf(0, 1, 2), queueWithAddition(listOf(0, 1), 1, 2, true))
    }
    @Test fun additionsUseVisibleShuffleOrder() {
        val shuffled = listOf(2, 0, 3, 1)
        assertEquals(listOf(2, 0, 4, 3, 1), queueWithAddition(shuffled, 0, 4, true))
        assertEquals(listOf(2, 0, 3, 1, 4), queueWithAddition(shuffled, 0, 4, false))
    }
    @Test fun emptyQueueAcceptsEitherAction() {
        assertEquals(listOf(0), queueWithAddition(emptyList(), -1, 0, true))
        assertEquals(listOf(0), queueWithAddition(emptyList(), -1, 0, false))
    }
    @Test fun customTimerBoundsAreExplicit() {
        assertEquals(1, timerMinutes("1")); assertEquals(1440, timerMinutes("1440"))
        listOf("", "0", "-1", "1441", "999999999999", "1.5", "hi").forEach { assertNull(timerMinutes(it)) }
    }
}
