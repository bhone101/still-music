package com.stillmusic.player

import kotlinx.coroutines.flow.collectLatest
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.background
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun LibraryScreen(destination: String, state: LibraryState, model: LibraryModel, playback: PlaybackModel, currentId: String?, connected: Boolean, addMusic: () -> Unit, settings: () -> Unit, deleteSong: (Song) -> Unit) {
    var tab by rememberSaveable { mutableIntStateOf(-1) }
    var search by rememberSaveable { mutableStateOf("") }
    var group by rememberSaveable { mutableStateOf<String?>(null) }
    var groupTitle by rememberSaveable { mutableStateOf("") }
    var adding by remember { mutableStateOf(false) }
    var deletePlaylist by remember { mutableStateOf<Playlist?>(null) }
    var editingSongs by remember { mutableStateOf<List<Song>?>(null) }
    var details by remember { mutableStateOf<Song?>(null) }
    var create by remember { mutableStateOf(false) }
    var playlistSongs by remember { mutableStateOf<List<Song>?>(null) }
    var creatingSongs by remember { mutableStateOf(emptyList<Song>()) }
    var selectedIds by remember { mutableStateOf(emptySet<String>()) }
    val history = remember { ListeningHistory.get(model.getApplication()) }
    val listens by history.plays.collectAsState()
    var rankingTime by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { rankingTime = System.currentTimeMillis(); kotlinx.coroutines.delay(60_000) } }
    LaunchedEffect(tab, group, search) { selectedIds = emptySet() }
    androidx.activity.compose.BackHandler(selectedIds.isNotEmpty()) { selectedIds = emptySet() }
    androidx.activity.compose.BackHandler(group != null && selectedIds.isEmpty()) { group = null }
    androidx.activity.compose.BackHandler(tab >= 0 && group == null && selectedIds.isEmpty()) { tab = -1 }
    val library = state.library
    val repeats = remember(listens, library.songs, rankingTime) { rankedRepeats(listens, library.songs.map { it.id }.toSet(), System.currentTimeMillis()) }
    val sortedLibrarySongs = remember(library.songs, state.sort, state.descending) { sortedSongs(library.songs, state.sort, state.descending) }
    val filtered = remember(sortedLibrarySongs, search, group, tab) { sortedLibrarySongs.filter { (group != null && tab == 3) || search.isBlank() || "${it.title} ${it.artist} ${it.album} ${it.folder} ${it.genre}".contains(search, true) } }
    Column(Modifier.fillMaxSize()) {
        val categoryTitle = when(tab) { 0 -> "Songs"; 1 -> "Albums"; 2 -> "Artists"; 4 -> "Folders"; 5 -> "Genres"; else -> "Library" }
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if(group != null || (tab >= 0)) IconButton(onClick = { if(group != null) group = null else tab = -1 }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
            }
            Text(if(group != null) groupTitle else when(destination) { "search" -> "Search"; "home" -> if(tab == -1) greeting() else categoryTitle; else -> categoryTitle },
                Modifier.weight(1f), style = MaterialTheme.typography.headlineLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if(tab == 3 && group != null && group != "on-repeat") IconButton(onClick = { adding = true }) { Icon(Icons.Default.Add, "Add songs") }
            if(group == null) {
                if(destination == "library") IconButton(onClick = { creatingSongs = emptyList(); create = true }) { Icon(Icons.Default.Add, "New playlist") }
                if(destination == "home") IconButton(onClick = model::scan, enabled = !state.scanning) { Icon(Icons.Default.Refresh, "Scan library") }
                IconButton(onClick = settings) { Icon(Icons.Default.Settings, "Settings", Modifier.size(22.dp)) }
            }
        }
        if(destination == "search") MusicSearch(search, { search = it; tab = if(it.isBlank()) -1 else 0; group = null }, Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 12.dp))
        if (tab == 0 || (group != null && tab != 3)) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (group == null) "${filtered.size} songs" else "", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            var sorting by remember { mutableStateOf(false) }
            Box {
                TextButton(onClick = { sorting = true }) { Text(state.sort.label) }
                DropdownMenu(sorting, { sorting = false }) {
                    SongSort.entries.forEach { option -> DropdownMenuItem(text = { Text(option.label) }, trailingIcon = { if (state.sort == option) Icon(Icons.Default.Check, "Selected") }, onClick = { model.sort(option); sorting = false }) }
                    HorizontalDivider()
                    DropdownMenuItem(text = { Text("Reverse order") }, trailingIcon = { if (state.descending) Icon(Icons.Default.Check, "Selected") }, onClick = { model.sort(state.sort, !state.descending); sorting = false })
                }
            }
        }
        if (state.scanning || state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        when {
            state.loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Loading library…") }
            library.songs.isEmpty() && tab != 3 -> Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Your music, here.", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(10.dp)); Text("Choose a folder to start listening.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(24.dp)); Button(onClick = addMusic, enabled = !state.scanning) { Icon(Icons.Default.Add, null); Spacer(Modifier.width(8.dp)); Text("Add music") }
            }
            destination == "home" && tab == -1 -> HomeBrowse(library, listens, connected,
                open = { category, key, title -> tab = category; group = key; groupTitle = title },
                play = { playback.play(library.songs, it.id) })
            destination == "search" && tab == -1 -> Column(Modifier.weight(1f)) {
                Text("Browse all", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(20.dp))
                LazyVerticalGrid(columns = GridCells.Fixed(2), contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(listOf(0 to "Songs", 1 to "Albums", 2 to "Artists", 5 to "Genres", 4 to "Folders")) { (index, title) ->
                        Box(Modifier.fillMaxWidth().heightIn(min = 88.dp).clip(RoundedCornerShape(8.dp)).background(if(index % 2 == 0) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant).clickable { tab = index }.padding(16.dp), contentAlignment = Alignment.BottomStart) {
                            Text(title, fontWeight = FontWeight.Bold, color = if(index % 2 == 0) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface)
                        }
                    }
                }
            }
            destination == "library" && tab == -1 -> Column(Modifier.weight(1f)) {
                Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(3 to "Playlists", 1 to "Albums", 2 to "Artists").forEach { (index, label) -> SuggestionChip(onClick = { tab = index }, label = { Text(label) }) }
                }
                LazyColumn {
                    item { Text("Your collections", Modifier.padding(20.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall) }
                    item { ListItem(headlineContent = { Text("Favorites") }, supportingContent = { Text("Playlist · ${library.favorites.size} songs") }, leadingContent = { CollectionBadge { Icon(Icons.Default.Favorite, null, tint = StillBlue) } }, modifier = Modifier.clickable { tab = 3; group = "favorites"; groupTitle = "Favorites" }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background)) }
                    item { ListItem(headlineContent = { Text("On Repeat") }, supportingContent = { Text("Your most-played songs") }, leadingContent = { CollectionBadge { Glyph("repeat", null) } }, modifier = Modifier.clickable { tab = 3; group = "on-repeat"; groupTitle = "On Repeat" }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background)) }
                    items(library.playlists, key = { "playlist:${it.id}" }) { playlist ->
                        ListItem(headlineContent = { Text(playlist.name) }, supportingContent = { Text("Playlist · ${playlist.songs.size} songs") }, leadingContent = { CollectionBadge { Glyph("queue", null) } }, modifier = Modifier.clickable { tab = 3; group = playlist.id; groupTitle = playlist.name }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background))
                    }
                    items(library.songs.distinctBy { it.albumKey }, key = { "album:${it.albumKey}" }) { song ->
                        ListItem(headlineContent = { Text(song.album) }, supportingContent = { Text("Album · ${song.artist}") }, leadingContent = { Art(song, Modifier.size(48.dp)) }, modifier = Modifier.clickable { tab = 1; group = song.albumKey; groupTitle = song.album }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background))
                    }
                    item { Row(Modifier.padding(20.dp)) { TextButton(onClick = addMusic) { Text("Add music") }; TextButton(onClick = model::scan, enabled = !state.scanning) { Text("Scan library") } } }
                }
            }
            tab == 0 || group != null -> {
                val songs = when(tab) {
                    1 -> filtered.filter { it.albumKey == group }
                    2 -> filtered.filter { it.artist == group }
                    4 -> filtered.filter { it.folderKey == group }
                    5 -> filtered.filter { it.genreLabel == group }
                    3 -> if (group == "favorites") filtered.filter { it.id in library.favorites } else if (group == "on-repeat") {
                        val byId = filtered.associateBy { it.id }; repeats.mapNotNull { byId[it] }
                    } else {
                        val ids = library.playlists.firstOrNull { it.id == group }?.songs.orEmpty()
                        val byId = filtered.associateBy { it.id }; ids.mapNotNull { byId[it] }
                    }
                    else -> filtered
                }
                val selectedSongs = songs.filter { it.id in selectedIds }
                if (group == "on-repeat") Text("Your most-played songs from the last 30 days.", Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = MaterialTheme.typography.bodySmall)
                if (selectedSongs.isNotEmpty()) Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { selectedIds = emptySet() }) { Text("Cancel") }
                    Text("${selectedSongs.size} selected", Modifier.weight(1f))
                    TextButton(onClick = { selectedIds = songs.map { it.id }.toSet() }) { Text("Select all") }
                    var selectionMenu by remember { mutableStateOf(false) }
                    Box {
                        IconButton(onClick = { selectionMenu = true }) { Icon(Icons.Default.MoreVert, "Selected song actions") }
                        DropdownMenu(selectionMenu, { selectionMenu = false }) {
                            DropdownMenuItem(text = { Text("Play next") }, enabled = connected, onClick = { playback.enqueue(selectedSongs, true); selectionMenu = false })
                            DropdownMenuItem(text = { Text("Add to queue") }, enabled = connected, onClick = { playback.enqueue(selectedSongs, false); selectionMenu = false })
                            DropdownMenuItem(text = { Text("Edit tags") }, enabled = state.editing?.running != true && !state.scanning, onClick = { editingSongs = selectedSongs; selectionMenu = false })
                            DropdownMenuItem(text = { Text("Add to playlist") }, onClick = { playlistSongs = selectedSongs; selectionMenu = false })
                            if (tab == 3 && group != "favorites" && group != "on-repeat") DropdownMenuItem(text = { Text("Remove from playlist") }, onClick = { model.removeFromPlaylist(group.orEmpty(), selectedSongs.map { it.id }); selectedIds = emptySet(); selectionMenu = false })
                        }
                    }
                }
                if (songs.isEmpty()) Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) { Text(if (search.isNotBlank()) "No matching music" else if (group == "on-repeat") "Keep listening. Your most-played songs will appear here automatically." else "No songs yet. Add songs from their ⋮ menu.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                val songListState = androidx.compose.foundation.lazy.rememberLazyListState()
                val context = androidx.compose.ui.platform.LocalContext.current
                LaunchedEffect(songs, songListState) {
                    snapshotFlow { songListState.firstVisibleItemIndex }.collectLatest { first ->
                        songs.drop(first).take(40).forEach { Artwork.load(context, it) }
                    }
                }
                LazyColumn(Modifier.weight(1f), state = songListState) { items(songs, key = { it.id }) { song ->
                    val targets = if (song.id in selectedIds) selectedSongs else listOf(song)
                    SongRow(song, song.id == currentId, song.id in library.favorites, connected,
                        selected = song.id in selectedIds, selectionCount = targets.size,
                        select = { selectedIds = if (song.id in selectedIds) selectedIds - song.id else selectedIds + song.id },
                        play = { if (selectedIds.isNotEmpty()) selectedIds = if (song.id in selectedIds) selectedIds - song.id else selectedIds + song.id else playback.play(songs, song.id) },
                        playNext = { playback.enqueue(targets, true) }, enqueue = { playback.enqueue(targets, false) }, favorite = { model.favorite(song.id) }, add = { playlistSongs = targets }, details = { details = song }, edit = { editingSongs = targets }, delete = { deleteSong(song) },
                        remove = if (tab == 3 && group != "favorites" && group != "on-repeat") ({ model.removeFromPlaylist(group.orEmpty(), targets.map { it.id }); selectedIds = selectedIds - targets.map { it.id }.toSet() }) else null)
                } }
            }
            tab == 1 || tab == 2 || tab == 4 || tab == 5 -> {
                val groups = remember(filtered, tab) { filtered.groupBy { when (tab) { 1 -> it.albumKey; 2 -> it.artist; 4 -> it.folderKey; else -> it.genreLabel } } }
                if(tab == 1) LazyVerticalGrid(columns = GridCells.Adaptive(140.dp), modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(20.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    items(groups.keys.sortedBy { groups[it]?.first()?.album }, key = { it }) { key ->
                        val album = groups.getValue(key).first()
                        Column(Modifier.clickable { group = key; groupTitle = album.album }) {
                            Art(album, Modifier.fillMaxWidth().aspectRatio(1f))
                            Text(album.album, Modifier.padding(top = 8.dp), style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(album.albumArtist.ifBlank { album.artist }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                } else
                LazyColumn(Modifier.weight(1f)) { items(groups.keys.sortedBy { if(tab == 1) groups[it]?.first()?.album else it }, key = { it }) { key ->
                    val songs = groups.getValue(key); val title = when (tab) { 1 -> songs.first().album; 4 -> songs.first().folderLabel; else -> key }
                    Row(Modifier.fillMaxWidth().clickable { group = key; groupTitle = title }.padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Art(songs.first(), Modifier.size(52.dp)); Column(Modifier.padding(start = 14.dp)) {
                            Text(title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${songs.size} ${if(songs.size == 1) "song" else "songs"}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                        }
                    }
                } }
            }
            else -> LazyColumn(Modifier.weight(1f)) {
                item { ListItem(headlineContent = { Text("Favorites") }, supportingContent = { val count = library.songs.count { it.id in library.favorites }; Text("$count ${if(count == 1) "song" else "songs"}") }, leadingContent = { CollectionBadge { Icon(Icons.Default.Favorite, null, tint = StillBlue) } }, modifier = Modifier.clickable { group = "favorites"; groupTitle = "Favorites" }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background)) }
                item { ListItem(headlineContent = { Text("On Repeat") }, supportingContent = { Text("${repeats.size} ${if (repeats.size == 1) "song" else "songs"}") }, leadingContent = { CollectionBadge { Glyph("repeat", null, tint = StillBlue) } }, modifier = Modifier.clickable { group = "on-repeat"; groupTitle = "On Repeat" }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background)) }
                items(library.playlists, key = { it.id }) { list -> ListItem(headlineContent = { Text(list.name) }, supportingContent = { val count = list.songs.count { id -> library.songs.any { it.id == id } }; Text("$count ${if(count == 1) "song" else "songs"}") }, leadingContent = { CollectionBadge { Glyph("queue", null, tint = StillBlue) } }, trailingContent = {
                    var menu by remember { mutableStateOf(false) }
                    Box { IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Actions for ${list.name}") }
                        DropdownMenu(menu, { menu = false }) { DropdownMenuItem(text = { Text("Delete playlist") }, onClick = { menu = false; deletePlaylist = list }) }
                    }
                }, modifier = Modifier.clickable { group = list.id; groupTitle = list.name }, colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background)) }
            }
        }
    }
    editingSongs?.let { TagEditor(it, model, playback) { editingSongs = null } }
    deletePlaylist?.let { list -> AlertDialog(onDismissRequest = { deletePlaylist = null }, title = { Text("Delete playlist?") },
        text = { Text("Delete “${list.name}”? Your audio files will be kept.") },
        confirmButton = { TextButton(onClick = { model.deletePlaylist(list.id); deletePlaylist = null }) { Text("Delete") } },
        dismissButton = { TextButton(onClick = { deletePlaylist = null }) { Text("Cancel") } }) }
    details?.let { song -> AlertDialog(onDismissRequest = { details = null }, title = { Text("Song details") }, text = {
        Column(Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())) {
            listOf("Title" to song.title, "Artist" to song.artist, "Album" to song.album, "Album artist" to song.albumArtist,
                "Format" to song.format, "Duration" to durationText(song.duration), "Sample rate" to if(song.sampleRate > 0) "${song.sampleRate} Hz" else "Unknown",
                "Bit depth" to if(song.bits > 0) "${song.bits} bit" else "Unknown", "File size" to android.text.format.Formatter.formatFileSize(androidx.compose.ui.platform.LocalContext.current, song.size),
                "File" to android.net.Uri.decode(song.id)).forEach { (label, value) ->
                Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 12.dp)); Text(value.ifBlank { "Unknown" })
            }
        }
    }, confirmButton = { TextButton(onClick = { details = null }) { Text("Close") } }) }
    if(adding && group != null) {
        var query by rememberSaveable { mutableStateOf("") }
        ModalBottomSheet(onDismissRequest = { adding = false }) {
            Column(Modifier.fillMaxWidth().fillMaxHeight(.85f).imePadding().padding(horizontal = 16.dp)) {
                Text("Add songs", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                MusicSearch(query, { query = it }, Modifier.fillMaxWidth().padding(vertical = 16.dp))
                LazyColumn { items(library.songs.filter { query.isBlank() || "${it.title} ${it.artist}".contains(query, true) }, key = { it.id }) { song ->
                    val alreadyAdded = if(group == "favorites") song.id in library.favorites else library.playlists.firstOrNull { it.id == group }?.songs?.contains(song.id) == true
                    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Art(song, Modifier.size(48.dp))
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) { Text(song.title, maxLines = 1, overflow = TextOverflow.Ellipsis); Text(song.artist, fontSize = 12.sp, maxLines = 1) }
                        IconButton(onClick = { if(group == "favorites") model.favorite(song.id) else model.addToPlaylist(group.orEmpty(), song.id) }, enabled = !alreadyAdded) {
                            Icon(if(alreadyAdded) Icons.Default.Check else Icons.Default.Add, if(alreadyAdded) "Already added" else "Add ${song.title}")
                        }
                    }
                } }
            }
        }
    }
    if (create) {
        var name by rememberSaveable { mutableStateOf("") }
        ModalBottomSheet(onDismissRequest = { create = false }, containerColor = MaterialTheme.colorScheme.surface) {
            Column(Modifier.fillMaxWidth().imePadding().padding(horizontal = 20.dp).padding(bottom = 28.dp)) {
                Text("New playlist", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(20.dp))
                OutlinedTextField(name, { name = it.take(100) }, label = { Text("Name") }, placeholder = { Text("Playlist name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(20.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(onClick = { create = false }, Modifier.weight(1f), shape = RoundedCornerShape(12.dp)) { Text("Cancel") }
                    Button(onClick = { model.createPlaylist(name, creatingSongs.map { it.id }); create = false }, Modifier.weight(1f), enabled = name.isNotBlank(), shape = RoundedCornerShape(12.dp)) { Text("Create") }
                }
            }
        }
    }
    playlistSongs?.let { songs -> AlertDialog(onDismissRequest = { playlistSongs = null }, title = { Text("Add ${songs.size} ${if (songs.size == 1) "song" else "songs"} to playlist") }, text = {
        Column(Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())) {
            TextButton(onClick = { creatingSongs = songs; playlistSongs = null; create = true }) { Text("Create a playlist…") }
            library.playlists.forEach { list -> TextButton(enabled = songs.any { it.id !in list.songs }, onClick = { model.addToPlaylist(list.id, songs.map { it.id }); playlistSongs = null }) { Text(list.name) } }
        }
    }, confirmButton = { TextButton(onClick = { playlistSongs = null }) { Text("Close") } }) }
}
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable private fun SongRow(song: Song, current: Boolean, isFavorite: Boolean, enabled: Boolean, selected: Boolean, selectionCount: Int, select: () -> Unit, play: () -> Unit, playNext: () -> Unit, enqueue: () -> Unit, favorite: () -> Unit, add: () -> Unit, remove: (() -> Unit)?, details: () -> Unit, edit: () -> Unit, delete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = .10f) else MaterialTheme.colorScheme.background).semantics { this.selected = selected }.combinedClickable(onClick = play, onLongClickLabel = "Select song", onLongClick = select).heightIn(min = 64.dp).padding(start = 16.dp, top = 4.dp, bottom = 4.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (selected) Icon(Icons.Default.Check, "Selected", Modifier.size(44.dp)) else Art(song, Modifier.size(44.dp))
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(song.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = if(current) StillBlue else MaterialTheme.colorScheme.onBackground, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(song.artist, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(if(song.duration > 0) durationText(song.duration) else "", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Actions for ${song.title}") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(if (selectionCount > 1) "Play $selectionCount songs next" else "Play next") }, enabled = enabled, onClick = { menu = false; playNext() })
                DropdownMenuItem(text = { Text(if (selectionCount > 1) "Add $selectionCount songs to queue" else "Add to queue") }, enabled = enabled, onClick = { menu = false; enqueue() })
                if (selectionCount == 1) DropdownMenuItem(text = { Text(if(isFavorite) "Remove from Favorites" else "Add to Favorites") }, onClick = { favorite(); menu = false })
                DropdownMenuItem(text = { Text("Add to playlist") }, onClick = { add(); menu = false })
                DropdownMenuItem(text = { Text("Edit tags") }, onClick = { menu = false; edit() })
                if (selectionCount == 1) DropdownMenuItem(text = { Text("Details") }, onClick = { menu = false; details() })
                if (selectionCount == 1) DropdownMenuItem(text = { Text("Delete song", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; delete() })
                if(remove != null) DropdownMenuItem(text = { Text("Remove from this playlist") }, onClick = { remove(); menu = false })
            }
        }
    }
}

@Composable private fun CollectionBadge(content: @Composable () -> Unit) {
    Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface) {
        Box(Modifier.size(52.dp), contentAlignment = Alignment.Center) { content() }
    }
}

private fun greeting(): String = when (java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)) {
    in 5..11 -> "Good morning"
    in 12..17 -> "Good afternoon"
    else -> "Good evening"
}

@Composable private fun HomeBrowse(library: Library, listens: List<Listen>, connected: Boolean, open: (Int, String, String) -> Unit, play: (Song) -> Unit) {
    val recent = remember(listens, library.songs) {
        val byId = library.songs.associateBy { it.id }
        listens.sortedByDescending { it.at }.distinctBy { it.id }.mapNotNull { byId[it.id] }.take(12)
    }
    val albums = remember(library.songs) { library.songs.distinctBy { it.albumKey }.take(20) }
    LazyColumn(contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item {
            val shortcuts = listOf(Triple(3, "favorites", "Favorites")) + library.playlists.take(1).map { Triple(3, it.id, it.name) } + albums.take(4).map { Triple(1, it.albumKey, it.album) }
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                shortcuts.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        pair.forEach { (category, id, title) ->
                            Row(Modifier.weight(1f).clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surface).clickable { open(category, id, title) }, verticalAlignment = Alignment.CenterVertically) {
                                if(category == 1) Art(albums.firstOrNull { it.albumKey == id }, Modifier.size(52.dp))
                                else Box(Modifier.size(52.dp).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) { if(id == "favorites") Icon(Icons.Default.Favorite, null, tint = StillBlue) else Glyph("queue", null) }
                                Text(title, Modifier.padding(8.dp), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            }
                        }
                        if(pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
        item {
            Text("Recently played", Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp), style = MaterialTheme.typography.headlineSmall)
            if(recent.isEmpty()) Text("Your listening history will appear here.", Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            else ArtworkShelf(recent, connected, play)
        }
        item {
            Text("Albums", Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp), style = MaterialTheme.typography.headlineSmall)
            ArtworkShelf(albums, true, { open(1, it.albumKey, it.album) }, albums = true)
        }
    }
}

@Composable private fun ArtworkShelf(songs: List<Song>, enabled: Boolean, open: (Song) -> Unit, albums: Boolean = false) {
    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(songs, key = { it.id }) { song ->
            Column(Modifier.width(116.dp).clickable(enabled = enabled) { open(song) }) {
                Art(song, Modifier.size(116.dp))
                Text(if(albums) song.album else song.title, Modifier.padding(top = 8.dp), fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(song.artist, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
