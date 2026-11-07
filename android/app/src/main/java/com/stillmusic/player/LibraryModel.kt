package com.stillmusic.player

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.UUID

data class LibraryState(val library: Library = Library(), val loading: Boolean = true, val scanning: Boolean = false, val deleting: Boolean = false, val message: String? = null, val dark: Boolean = true, val online: Boolean = false, val sort: SongSort = SongSort.Title, val descending: Boolean = false, val editing: TagEditProgress? = null, val tagRecoveryCount: Int = 0)
class LibraryModel(app: Application) : AndroidViewModel(app) {
    private val store = LibraryStore(app)
    private val preferences = app.getSharedPreferences("still-v2", 0)
    private val saves = Mutex()
    private val mutable = MutableStateFlow(LibraryState(dark = preferences.getBoolean("dark", true), online = preferences.getBoolean("online", false), sort = SongSort.entries.firstOrNull { it.name == preferences.getString("sort", "Title") } ?: SongSort.Title, descending = preferences.getBoolean("descending", false)))
    val state = mutable.asStateFlow()
    private var readable = false
    private var lastSaved: Library? = null
    init { viewModelScope.launch {
        try { val data = withContext(Dispatchers.IO) { store.read() }; readable = true; lastSaved = data; mutable.value = mutable.value.copy(library = data, loading = false)
            val interrupted = withContext(Dispatchers.IO) { TagWriter.recoveryCount(getApplication()) }
            mutable.value = mutable.value.copy(tagRecoveryCount = interrupted)
            if (interrupted > 0) report("$interrupted interrupted tag edit(s) have originals retained in app storage. Use Recover interrupted edits in Settings before editing those files again.")
            val repaired = withContext(Dispatchers.IO) { data.songs.filter { it.duration <= 0 && it.format.lowercase() in setOf("m4a", "m4b") }.mapNotNull { original -> store.repairMp4(original).takeIf { it != original }?.let { it.id to it } }.toMap() }
            if(repaired.isNotEmpty()) update { current -> current.copy(songs = current.songs.map { song -> repaired[song.id]?.takeIf { it.modified == song.modified && it.size == song.size }?.let { fixed -> fixed.copy(duration = song.duration.takeIf { it > 0 } ?: fixed.duration) } ?: song }) }
        }
        catch (e: Exception) { if (e is CancellationException) throw e; mutable.value = mutable.value.copy(loading = false, message = "The saved library could not be read. It has been preserved; please report this error before rebuilding it.") }
    } }
    fun sort(value: SongSort, descending: Boolean = state.value.descending) {
        preferences.edit().putString("sort", value.name).putBoolean("descending", descending).apply()
        mutable.value = mutable.value.copy(sort = value, descending = descending)
    }
    fun dismissMessage() { mutable.value = mutable.value.copy(message = null) }
    fun theme(dark: Boolean) { preferences.edit().putBoolean("dark", dark).apply(); mutable.value = mutable.value.copy(dark = dark) }
    fun online(enabled: Boolean) { preferences.edit().putBoolean("online", enabled).apply(); mutable.value = mutable.value.copy(online = enabled) }
    fun addFolder(uri: Uri) {
        try {
            getApplication<Application>().contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            val folders = preferences.getStringSet("folders", emptySet()).orEmpty().toSet() + uri.toString()
            preferences.edit().putStringSet("folders", folders).apply()
            scan()
        } catch (_: SecurityException) { mutable.value = mutable.value.copy(message = "Permission was not granted. Please choose the music folder again.") }
    }
    fun scan() {
        if (!readable || mutable.value.loading || mutable.value.scanning || mutable.value.deleting || mutable.value.editing?.running == true) return
        val roots = preferences.getStringSet("folders", emptySet()).orEmpty().toList()
        if (roots.isEmpty()) { mutable.value = mutable.value.copy(message = "Use Add music to choose a folder first."); return }
        mutable.value = mutable.value.copy(scanning = true)
        viewModelScope.launch {
            var songs = mutable.value.library.songs
            var failures = 0
            try {
                for (root in roots) {
                    try {
                        val found = withContext(Dispatchers.IO) { store.scan(Uri.parse(root), songs) }
                        songs = (songs.filter { it.root != root } + found).distinctBy { it.id }
                    } catch (e: Exception) { if (e is CancellationException) throw e; failures++ }
                }
                update { it.copy(songs = songs.sortedBy { s -> s.title.lowercase() }) }
                if (failures > 0) mutable.value = mutable.value.copy(message = "$failures folder(s) could not be scanned. Their saved songs were kept; reconnect storage or choose the folder again.")
            } finally { mutable.value = mutable.value.copy(scanning = false) }
        }
    }
    fun recordDuration(id: String, duration: Long) {
        if(duration > 0 && mutable.value.library.songs.any { it.id == id && it.duration <= 0 }) update { it.copy(songs = it.songs.map { song -> if(song.id == id && song.duration <= 0) song.copy(duration = duration) else song }) }
    }
    fun favorite(id: String) = update { it.copy(favorites = if (id in it.favorites) it.favorites - id else it.favorites + id) }
    fun createPlaylist(name: String, songIds: List<String> = emptyList()) {
        val clean = name.trim().take(100)
        if (clean.isEmpty()) return
        if (mutable.value.library.playlists.any { it.name.equals(clean, true) }) { mutable.value = mutable.value.copy(message = "A playlist with that name already exists."); return }
        update { it.copy(playlists = it.playlists + Playlist(UUID.randomUUID().toString(), clean, songIds.distinct())) }
    }
    fun addToPlaylist(playlistId: String, songId: String) = addToPlaylist(playlistId, listOf(songId))
    fun addToPlaylist(playlistId: String, songIds: List<String>) = update { library -> library.copy(playlists = library.playlists.map { if (it.id == playlistId) it.copy(songs = (it.songs + songIds).distinct()) else it }) }
    fun removeFromPlaylist(playlistId: String, songId: String) = removeFromPlaylist(playlistId, listOf(songId))
    fun removeFromPlaylist(playlistId: String, songIds: List<String>) = update { library -> library.copy(playlists = library.playlists.map { if (it.id == playlistId) it.copy(songs = it.songs - songIds.toSet()) else it }) }
    fun deletePlaylist(id: String) = update { it.copy(playlists = it.playlists.filterNot { list -> list.id == id }) }
    fun report(message: String) { mutable.value = mutable.value.copy(message = message) }
    fun recoverTagEdits() {
        if (state.value.scanning || state.value.deleting || state.value.editing?.running == true) return
        mutable.value = mutable.value.copy(editing = TagEditProgress(state.value.tagRecoveryCount, recovering = true))
        viewModelScope.launch {
            val failures = withContext(Dispatchers.IO) { TagWriter.recover(getApplication()) }
            val remaining = withContext(Dispatchers.IO) { TagWriter.recoveryCount(getApplication()) }
            mutable.value = mutable.value.copy(editing = null, tagRecoveryCount = remaining)
            report(if (failures.isEmpty()) "Interrupted edits recovered. Scan the library to refresh song details." else failures.joinToString("\n"))
        }
    }
    fun dismissTagProgress() { if (state.value.editing?.running != true) mutable.value = mutable.value.copy(editing = null) }
    fun cancelTagEditing() { mutable.value = mutable.value.copy(editing = state.value.editing?.copy(cancelling = true)) }
    fun grantEditing(song: Song, uri: Uri): Boolean {
        if (uri.toString() != song.root) { report("Choose this song’s original music folder to edit its tags."); return false }
        return try {
            getApplication<Application>().contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            canDelete(song).also { if (!it) report("Write permission was not granted. Tags were kept.") }
        } catch (_: SecurityException) { report("Write permission was not granted. Tags were kept."); false }
    }
    internal fun editTags(songs: List<Song>, changes: TagChanges) {
        if (!readable || state.value.scanning || state.value.deleting || state.value.editing?.running == true) { report("Wait for the current library operation to finish."); return }
        mutable.value = mutable.value.copy(editing = TagEditProgress(songs.size))
        viewModelScope.launch {
            val updated = mutableMapOf<String, Song>()
            try {
                for (song in songs) {
                    if (state.value.editing?.cancelling == true) break
                    var failure: String? = null
                    try {
                        check(canDelete(song)) { "Write permission is required" }
                        updated[song.id] = withContext(Dispatchers.IO) { TagWriter.write(getApplication(), song, changes) }
                    } catch (e: Exception) { if (e is CancellationException) throw e; failure = "${song.title}: ${e.message ?: "Could not update tags"}" }
                    val current = state.value.editing ?: break
                    mutable.value = mutable.value.copy(editing = current.copy(completed = current.completed + 1,
                        updated = updated.size, failures = current.failures + listOfNotNull(failure)))
                }
            } finally {
                if (updated.isNotEmpty()) update { library -> library.copy(songs = library.songs.map { updated[it.id] ?: it }) }
                val recoverable = withContext(Dispatchers.IO) { TagWriter.recoveryCount(getApplication()) }
                mutable.value = mutable.value.copy(editing = state.value.editing?.copy(running = false), tagRecoveryCount = recoverable)
            }
        }
    }
    fun canDelete(song: Song): Boolean = getApplication<Application>().contentResolver.persistedUriPermissions.any {
        it.isWritePermission && it.uri.toString() == song.root
    }
    fun grantDeletion(song: Song, uri: Uri): Boolean {
        if (uri.toString() != song.root) { report("Choose the original music folder to allow deletion."); return false }
        return try {
            getApplication<Application>().contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            canDelete(song).also { if(!it) report("Write permission was not granted. The audio file was kept.") }
        } catch (_: SecurityException) { report("Write permission was not granted. The audio file was kept."); false }
    }
    fun deleteSong(song: Song, before: () -> Unit, done: () -> Unit) {
        if (!readable || mutable.value.scanning || mutable.value.deleting || mutable.value.editing?.running == true) { report("Wait for the current library operation to finish, then try again."); return }
        if (!canDelete(song)) { report("Write permission is required. The audio file was kept."); return }
        mutable.value = mutable.value.copy(deleting = true)
        before()
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val resolver = getApplication<Application>().contentResolver
                    val uri = Uri.parse(song.id)
                    require(android.provider.DocumentsContract.isDocumentUri(getApplication(), uri))
                    val mime = resolver.getType(uri)
                    require(mime != null && mime != android.provider.DocumentsContract.Document.MIME_TYPE_DIR)
                    check(android.provider.DocumentsContract.deleteDocument(resolver, uri))
                }
                update { it.withoutSong(song.id) }
                done()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                report("The audio file could not be deleted. Its library entry was kept. Check folder permissions and storage availability.")
            } finally { mutable.value = mutable.value.copy(deleting = false) }
        }
    }
    private fun update(transform: (Library) -> Library) {
        if (!readable) return
        mutable.value = mutable.value.copy(library = transform(mutable.value.library))
        viewModelScope.launch { saves.withLock {
            val snapshot = mutable.value.library
            try { if (snapshot != lastSaved) { withContext(Dispatchers.IO) { store.write(snapshot) }; lastSaved = snapshot } }
            catch (e: Exception) { if (e is CancellationException) throw e; mutable.value = mutable.value.copy(message = "Changes could not be saved. Check available storage.") }
        } }
    }
}
