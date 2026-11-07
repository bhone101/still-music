package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(AudioHostTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class LibraryCatalogTest {
    private fun song(id: String, root: String = "content://root/a") = Song("content://songs/$id", id, "Artist", "Album", "", 100, "mp3", root = root, folder = "Music")
    @Test fun carBrowserPreservesPlaylistOrderAndHidesMissingSongs() {
        val a = song("a"); val b = song("b")
        val library = Library(listOf(a, b), setOf(b.id), listOf(Playlist("p", "Playlist", listOf(b.id, "missing", a.id))))
        val catalog = LibraryCatalog(RuntimeEnvironment.getApplication()) { it.run() }
        assertEquals(listOf(b.id, a.id), catalog.children(library, "playlist:p").map { it.mediaId })
        assertEquals(listOf(b.id), catalog.children(library, "favorites").map { it.mediaId })
        assertTrue(catalog.children(library, "root").all { it.mediaMetadata.isBrowsable == true && it.mediaMetadata.isPlayable == false })
        assertTrue(catalog.children(library, "songs").all { it.mediaMetadata.isPlayable == true })
    }
    @Test fun everyBrowsableNodeCanBeResolvedForSubscriptions() {
        val a = song("a")
        val library = Library(listOf(a), playlists = listOf(Playlist("p", "P", listOf(a.id))))
        val catalog = LibraryCatalog(RuntimeEnvironment.getApplication()) { it.run() }
        val roots = catalog.children(library, "root")
        val nested = listOf("albums", "artists", "folders", "playlists").flatMap { catalog.children(library, it) }
        assertEquals(true, catalog.item(library, "root")?.mediaMetadata?.isBrowsable)
        (roots + nested).forEach { node -> assertEquals(true, catalog.item(library, node.mediaId)?.mediaMetadata?.isBrowsable) }
        assertNull(catalog.item(library, "album:missing"))
    }
    @Test fun sameNamedFoldersOnDifferentRootsRemainSeparate() {
        val a = song("a"); val b = song("b", "content://root/b")
        val library = Library(listOf(a, b))
        val catalog = LibraryCatalog(RuntimeEnvironment.getApplication()) { it.run() }
        val folders = catalog.children(library, "folders")
        assertEquals(2, folders.size)
        assertEquals(listOf(a.id), catalog.children(library, folders.first().mediaId).map { it.mediaId })
        assertEquals(listOf(b.id), catalog.children(library, folders.last().mediaId).map { it.mediaId })
    }
}
