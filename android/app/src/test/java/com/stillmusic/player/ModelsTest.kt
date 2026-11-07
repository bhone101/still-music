package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test

class ModelsTest {
    @Test fun modeCycleReturnsToNormal() {
        var mode = PlayMode.Normal
        val values = List(2) { mode.also { mode = mode.next() } }
        assertEquals(listOf(PlayMode.Normal, PlayMode.Shuffle), values)
        assertEquals(PlayMode.Normal, mode)
    }
    @Test fun repeatedTimestampsAndOffsetAreSorted() {
        val result = LyricParser.parse("[offset:-250]\n[00:02.50][00:01.5]Words\n[00:00.10]Start")
        assertTrue(result.synced)
        assertEquals(listOf(0L,1250L,2250L), result.lines.map { it.timeMs })
        assertEquals("Words",result.lines.last().text)
    }
    @Test fun lyricsDoNotHighlightBeforeFirstLine() {
        val lines = LyricParser.parse("[00:01]A\n[00:02]B").lines
        assertEquals(-1,LyricParser.activeIndex(lines,999))
        assertEquals(0,LyricParser.activeIndex(lines,1000))
        assertEquals(1,LyricParser.activeIndex(lines,2500))
        assertEquals(-1,LyricParser.activeIndex(emptyList(),2500))
    }
    @Test fun plainLyricsKeepContentAndRemoveMetadata() {
        val result = LyricParser.parse("[ar:Artist]\nOne\n\nTwo")
        assertFalse(result.synced)
        assertEquals(listOf("One","Two"),result.lines.map { it.text })
    }
    @Test fun enormousTimestampDoesNotOverflow() {
        assertFalse(LyricParser.parse("[99999999999999999999999:00]Words").synced)
        assertTrue(LyricParser.parse("[offset:99999999999999999999999]\n[00:01]Words").synced)
    }
    @Test fun durationsHandleMissingValuesAndLongTracks() {
        assertEquals("0:00",durationText(-1))
        assertEquals("61:02",durationText(3662000))
    }
    @Test fun albumsWithSameNameButDifferentArtistsStaySeparate() {
        val a = Song("1","A","Singer A","Greatest Hits","",0,"mp3")
        assertNotEquals(a.albumKey,a.copy(artist="Singer B").albumKey)
        assertEquals(a.copy(albumArtist="Various").albumKey,a.copy(artist="Singer B",albumArtist="Various").albumKey)
    }
}
