package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test

class ListeningHistoryTest {
    @Test fun ranksRecentAvailableSongsByCountThenRecency() {
        val now = REPEAT_WINDOW_MS * 2
        val plays = listOf(Listen("a", now - 2), Listen("a", now - 1), Listen("b", now),
            Listen("old", now - REPEAT_WINDOW_MS), Listen("removed", now), Listen("future", now + 1))
        assertEquals(listOf("a", "b"), rankedRepeats(plays, setOf("a", "b", "old", "future"), now))
        assertEquals(emptyList<String>(), rankedRepeats(plays, setOf("a", "b"), now + REPEAT_WINDOW_MS))
        assertEquals(listOf("b", "a"), rankedRepeats(listOf(Listen("a", now - 1), Listen("b", now)), setOf("a", "b"), now))
    }
    @Test fun limitsPlaylistToThirtySongs() {
        val plays = (1..40).map { Listen("$it", it.toLong()) }
        assertEquals(30, rankedRepeats(plays, plays.map { it.id }.toSet(), 40).size)
    }
    @Test fun qualifiesOnlyOnceAndDoesNotCountPauseOrSeek() {
        val session = ListenSession()
        assertFalse(session.observe(0, 120_000, true, 0))
        assertFalse(session.observe(90_000, 120_000, true, 1000))
        session.interrupt()
        assertFalse(session.observe(0, 120_000, true, 10_000))
        for (i in 1..29) assertFalse(session.observe(i * 1000L, 120_000, true, 10_000 + i * 1000L))
        assertFalse(session.observe(29_000, 120_000, false, 100_000))
        assertFalse(session.observe(29_000, 120_000, true, 101_000))
        assertTrue(session.observe(30_000, 120_000, true, 102_000))
        assertFalse(session.observe(31_000, 120_000, true, 103_000))
    }
    @Test fun shortTracksQualifyAfterHalfTheirDuration() {
        val session = ListenSession()
        for (i in 0..4) assertFalse(session.observe(i * 1000L, 10_000, true, i * 1000L))
        assertTrue(session.observe(5000, 10_000, true, 5000))
    }
}
