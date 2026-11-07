package com.stillmusic.player

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import java.util.concurrent.Executor

/** The same saved library is exposed to trusted car/media browsers; IO stays off the player thread. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class LibraryCatalog(private val context: Context, private val executor: Executor) : MediaLibrarySession.Callback {
    private var cached: Library? = null
    private var stamp = -1L
    private fun library(): Library {
        val modified = java.io.File(context.filesDir, "library-v2.json").lastModified()
        if (cached == null || stamp != modified) { cached = LibraryStore(context).read(); stamp = modified }
        return cached ?: Library()
    }
    private fun <T> background(work: () -> T): ListenableFuture<T> {
        val result = SettableFuture.create<T>()
        executor.execute { try { result.set(work()) } catch (e: Exception) { result.setException(e) } }
        return result
    }
    override fun onGetLibraryRoot(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, params: LibraryParams?): ListenableFuture<LibraryResult<MediaItem>> =
        Futures.immediateFuture(LibraryResult.ofItem(folder("root", "Still Music"), params))
    override fun onGetChildren(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = background {
        val children = children(library(), parentId)
        LibraryResult.ofItemList(pageItems(children, page, pageSize), params)
    }
    override fun onGetItem(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, mediaId: String): ListenableFuture<LibraryResult<MediaItem>> = background {
        val item = item(library(), mediaId)
        if (item != null) LibraryResult.ofItem(item, null) else LibraryResult.ofError(androidx.media3.session.SessionError.ERROR_BAD_VALUE)
    }
    override fun onSubscribe(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> {
        val result = SettableFuture.create<LibraryResult<Void>>()
        executor.execute {
            try {
                val data = library()
                val parent = item(data, parentId)
                val count = children(data, parentId).size
                android.os.Handler(session.player.applicationLooper).post {
                    if (parent?.mediaMetadata?.isBrowsable == true) {
                        session.notifyChildrenChanged(browser, parentId, count, params)
                        result.set(LibraryResult.ofVoid())
                    } else result.set(LibraryResult.ofError(androidx.media3.session.SessionError.ERROR_BAD_VALUE))
                }
            } catch (e: Exception) { result.setException(e) }
        }
        return result
    }
    internal fun item(library: Library, id: String): MediaItem? {
        if (id == "root") return folder("root", "Still Music")
        library.songs.firstOrNull { it.id == id }?.let { return it.asMediaItem() }
        children(library, "root").firstOrNull { it.mediaId == id }?.let { return it }
        val category = when {
            id.startsWith("album:") -> "albums"
            id.startsWith("artist:") -> "artists"
            id.startsWith("folder:") -> "folders"
            id.startsWith("playlist:") -> "playlists"
            else -> return null
        }
        return children(library, category).firstOrNull { it.mediaId == id }
    }
    override fun onAddMediaItems(session: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>): ListenableFuture<MutableList<MediaItem>> = background {
        val data = library()
        val byId = data.songs.associateBy { it.id }
        mediaItems.flatMap { requested ->
            val query = requested.requestMetadata.searchQuery
            val songs = if (!query.isNullOrBlank()) search(data, query) else listOfNotNull(byId[requested.mediaId])
            songs.map { song -> song.asMediaItem().let { resolved ->
                resolved.buildUpon().setMediaMetadata(resolved.mediaMetadata.buildUpon().setExtras(
                    requested.mediaMetadata.extras ?: resolved.mediaMetadata.extras).build()).build()
            } }
        }.toMutableList()
    }
    override fun onSearch(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> {
        val result = SettableFuture.create<LibraryResult<Void>>()
        executor.execute {
            try {
                val count = search(library(), query).size
                android.os.Handler(session.player.applicationLooper).post { session.notifySearchResultChanged(browser, query, count, params); result.set(LibraryResult.ofVoid()) }
            } catch (e: Exception) { result.setException(e) }
        }
        return result
    }
    override fun onGetSearchResult(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, page: Int, pageSize: Int, params: LibraryParams?): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = background {
        LibraryResult.ofItemList(pageItems(search(library(), query).map { it.asMediaItem() }, page, pageSize), params)
    }
    private fun search(library: Library, query: String) = library.songs.filter { "${it.title} ${it.artist} ${it.album}".contains(query, true) }
    internal fun children(library: Library, id: String): List<MediaItem> = when {
        id == "root" -> listOf(folder("songs", "Songs"), folder("albums", "Albums"), folder("artists", "Artists"), folder("favorites", "Favorites"), folder("on-repeat", "On Repeat"), folder("playlists", "Playlists"), folder("folders", "Folders"))
        id == "songs" -> library.songs.map { it.asMediaItem() }
        id == "favorites" -> library.songs.filter { it.id in library.favorites }.map { it.asMediaItem() }
        id == "on-repeat" -> rankedRepeats(ListeningHistory.get(context).plays.value, library.songs.map { it.id }.toSet(), System.currentTimeMillis()).mapNotNull { key -> library.songs.firstOrNull { it.id == key }?.asMediaItem() }
        id == "albums" -> library.songs.distinctBy { it.albumKey }.map { folder("album:${it.albumKey}", it.album) }
        id == "artists" -> library.songs.map { it.artist }.distinct().map { folder("artist:$it", it) }
        id == "folders" -> library.songs.distinctBy { it.folderKey }.map { folder("folder:${it.folderKey}", it.folderLabel) }
        id == "playlists" -> library.playlists.map { folder("playlist:${it.id}", it.name) }
        id.startsWith("playlist:") -> library.playlists.firstOrNull { it.id == id.removePrefix("playlist:") }?.songs.orEmpty().mapNotNull { key -> library.songs.firstOrNull { it.id == key }?.asMediaItem() }
        else -> library.songs.filter { when { id.startsWith("album:") -> it.albumKey == id.removePrefix("album:"); id.startsWith("artist:") -> it.artist == id.removePrefix("artist:"); id.startsWith("folder:") -> it.folderKey == id.removePrefix("folder:"); else -> false } }.map { it.asMediaItem() }
    }
    private fun folder(id: String, title: String) = MediaItem.Builder().setMediaId(id).setMediaMetadata(MediaMetadata.Builder().setTitle(title).setIsBrowsable(true).setIsPlayable(false).setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED).build()).build()
}
internal fun Song.asMediaItem(): MediaItem = SavedTrack(id, title, artist, album, java.util.UUID.randomUUID().toString()).mediaItem()
internal fun <T> pageItems(items: List<T>, page: Int, size: Int): List<T> {
    if (page < 0 || size <= 0) return emptyList()
    val start = page.toLong() * size
    if (start >= items.size) return emptyList()
    return items.subList(start.toInt(), (start + size).coerceAtMost(items.size.toLong()).toInt())
}
