package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(AudioHostTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class LibraryStoreTest {
    private val context get() = RuntimeEnvironment.getApplication()
    @Before fun cleanFixture() {
        listOf("library-v2.json", "library-v2.json.bak", "library-v2.json.new").forEach { File(context.filesDir,it).delete() }
    }
    @Test fun libraryPlaylistsAndFavoritesSurviveReload() {
        val song = Song("content://test/document/one", "Song", "Artist", "Album", "Album artist", 120000, "flac", 96000, 24, "content://test/tree/music", 1234, 4567, "content://test/lyrics")
        val library = Library(listOf(song),setOf(song.id),listOf(Playlist("p1","Listening",listOf(song.id))))
        LibraryStore(context).write(library)
        assertEquals(library,LibraryStore(context).read())
    }
    @Test fun missingLibraryStartsEmpty() { assertEquals(Library(),LibraryStore(context).read()) }
    @Test fun corruptLibraryIsNotSilentlyOverwritten() {
        val file = File(context.filesDir,"library-v2.json"); file.writeText("not valid JSON")
        try { LibraryStore(context).read(); fail("Expected corrupt library to be reported") } catch (_: org.json.JSONException) { }
        assertEquals("not valid JSON",file.readText())
    }
    @Test fun atomicBackupIsRecoveredWhenBaseIsMissing() {
        val library = Library(favorites=setOf("a"))
        LibraryStore(context).write(library)
        val base = File(context.filesDir,"library-v2.json")
        assertTrue(base.renameTo(File(context.filesDir,"library-v2.json.bak")))
        assertEquals(library,LibraryStore(context).read())
    }
}
