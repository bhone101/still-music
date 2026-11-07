package com.stillmusic.player

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(AudioHostTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class LyricsRepositoryTest {
    private val song = Song("content://test/document/lyrics", "Test song", "Test artist", "Test album", "", 120000, "m4a")
    @Test fun plainLocalLyricsNeverTriggerSearch() = runBlocking {
        val plain = LyricParser.parse("Local plain lyrics")
        assertEquals(plain, resolveLyrics(true, { plain }, { error("Cache must not replace local lyrics") }, { error("Must not search") }))
    }
    @Test fun syncedLocalLyricsNeverTriggerSearch() = runBlocking {
        val synced = LyricParser.parse("[00:01]Local synced lyrics")
        assertEquals(synced, resolveLyrics(true, { synced }, { error("Must not check cache") }, { error("Must not search") }))
    }
    @Test fun cachedLyricsWorkWithOnlineSettingOff() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val lyrics = LyricParser.parse("[00:01]Saved lyric")
        LyricsRepository(context).save(song, lyrics)
        assertEquals(lyrics, resolveLyrics(false, { Lyrics(emptyList(), false) }, { LyricsRepository(context).cached(song) }, { error("Must not search") }))
    }
    @Test fun missingLyricsSearchExactlyOnce() = runBlocking {
        var calls = 0
        val found = LyricParser.parse("Online plain lyrics")
        assertEquals(found, resolveLyrics(true, { Lyrics(emptyList(), false) }, { null }, { calls++; found }))
        assertEquals(1, calls)
    }
    @Test fun disabledSearchDoesNotSendMetadata() = runBlocking {
        assertTrue(resolveLyrics(false, { Lyrics(emptyList(), false) }, { null }, { error("Must not search") }).lines.isEmpty())
    }
    @Test fun plainOnlineResultIsAcceptedWhenSyncedIsNull() {
        val record = JSONObject().put("trackName", song.title).put("artistName", song.artist).put("albumName", song.album).put("duration", 120)
            .put("syncedLyrics", JSONObject.NULL).put("plainLyrics", "Plain result")
        assertEquals(LyricParser.parse("Plain result"), selectLyrics(JSONArray().put(record), song))
        record.put("syncedLyrics", "[00:01]Synced result")
        assertTrue(selectLyrics(JSONArray().put(record), song)!!.synced)
        record.put("duration", 180)
        assertNull(selectLyrics(JSONArray().put(record), song))
    }
    private fun record(title: String = song.title, artist: String = song.artist, seconds: Int = 120) = JSONObject()
        .put("trackName",title).put("artistName",artist).put("albumName",song.album).put("duration",seconds)
        .put("syncedLyrics","[00:01]A test line").put("plainLyrics","A test line")
    @Test fun unknownDurationStillMatchesKnownArtistAndTitle() {
        assertNotNull(selectLyrics(JSONArray().put(record()), song.copy(duration = 0)))
    }
    @Test fun punctuationAndRemasterLabelsDoNotHideMatches() {
        val tagged = song.copy(title = "Don't Stop - 2011 Remaster", artist = "Beyoncé")
        assertNotNull(selectLyrics(JSONArray().put(record("Don’t Stop", "Beyonce")), tagged))
        assertEquals("Test song", cleanTitle("Test song (2020 Remastered)"))
        assertEquals("Test song (Live)", cleanTitle("Test song (Live)"))
    }
    @Test fun mismatchedArtistAndDifferentLiveVersionsAreNotAccepted() {
        assertNull(selectLyrics(JSONArray().put(record(artist = "Other artist")), song))
        assertNull(selectLyrics(JSONArray().put(record(title = "Test song (Live)")), song))
    }
    @Test fun durationMismatchUsesPlainTextInsteadOfMisleadingTiming() {
        assertFalse(selectLyrics(JSONArray().put(record(seconds = 130)), song)!!.synced)
    }
    @Test fun unknownArtistMustNotChooseBetweenUnrelatedSongs() {
        assertNull(selectLyrics(JSONArray().put(record()).put(record(artist = "Someone else")), song.copy(artist = "Unknown artist")))
    }
    @Test fun brokenLocalReaderStillAllowsOnlineLookup() = runBlocking {
        val lyrics = LyricParser.parse("Recovered online")
        assertEquals(lyrics, resolveLyrics(true, { throw java.io.IOException("Unsupported embedded metadata") }, { null }, { lyrics }))
    }
    @Test fun burmeseVowelsAndToneMarksArePreserved() {
        assertNotEquals(normalized("က"), normalized("ကာ"))
        assertNotEquals(normalized("က"), normalized("ကိ"))
        assertEquals("beyonce", normalized("Beyoncé"))
    }
    @Test fun cancellationDoesNotStartNetworkLookup() = runBlocking {
        try { resolveLyrics(true, { throw kotlinx.coroutines.CancellationException() }, { error("Must cancel") }, { error("Must cancel") }); fail("Expected cancellation") }
        catch (_: kotlinx.coroutines.CancellationException) { }
    }
}
