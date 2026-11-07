package com.stillmusic.player

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { StillApp() }
    }
}
@Composable private fun StillApp(libraryModel: LibraryModel = viewModel(), playbackModel: PlaybackModel = viewModel()) {
    val library by libraryModel.state.collectAsStateWithLifecycle()
    val playback by playbackModel.state.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableStateOf("library") }
    var destination by rememberSaveable { mutableStateOf("home") }
    val current = remember(library.library.songs, playback.id) { library.library.songs.firstOrNull { it.id == playback.id } }
    LaunchedEffect(playback.id, playback.duration) { playback.id?.let { libraryModel.recordDuration(it, playback.duration) } }
    val lyricsRepository = remember { LyricsRepository(libraryModel.getApplication()) }
    LaunchedEffect(current, library.online) {
        if(library.online && current != null) try {
            resolveLyrics(true, { lyricsRepository.local(current) }, { lyricsRepository.cached(current) }, { lyricsRepository.online(current) })
        } catch(e: Exception) { if(e is kotlinx.coroutines.CancellationException) throw e }
    }
    val screens = androidx.compose.runtime.saveable.rememberSaveableStateHolder()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri -> uri?.let(libraryModel::addFolder) }
    var deleteCandidate by remember { mutableStateOf<Song?>(null) }
    var awaitingPermission by rememberSaveable { mutableStateOf<String?>(null) }
    fun delete(song: Song) = libraryModel.deleteSong(song, { playbackModel.pauseForDeletion(song.id) }, { playbackModel.removeSong(song.id) })
    val deletionPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        val song = library.library.songs.firstOrNull { it.id == awaitingPermission }
        awaitingPermission = null
        if(uri != null && song != null && libraryModel.grantDeletion(song, uri)) delete(song)
    }
    val addMusic = { picker.launch(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) { lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { while(true) { playbackModel.tick(); delay(400) } } }
    BackHandler(page == "library" && destination != "home") { destination = "home" }
    BackHandler(page != "library") { page = if(page == "queue") "player" else "library" }
    val activity = androidx.activity.compose.LocalActivity.current as? ComponentActivity
    SideEffect {
        val style = if(library.dark) androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT) else androidx.activity.SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
        activity?.enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
    }
    StillTheme(library.dark) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
                Box(Modifier.weight(1f)) {
                    screens.SaveableStateProvider(if (page == "library") destination else page) { when(page) {
                        "settings" -> SettingsScreen(library, libraryModel, addMusic) { page = "library" }
                        "player" -> PlayerScreen(current, playback, playbackModel, library.online, current?.id in library.library.favorites, { current?.let { libraryModel.favorite(it.id) } }, { page = "library" }, { page = "queue" })
                        "queue" -> QueueScreen(playback, playbackModel, library.library.songs) { page = "player" }
                        else -> LibraryScreen(destination, library, libraryModel, playbackModel, playback.id, playback.connected, addMusic, { page = "settings" }, { deleteCandidate = it })
                    } }
                }
                if(page == "library") {
                    MiniPlayer(current, playback, { page = "player" }, playbackModel::toggle, current?.id in library.library.favorites) { current?.let { libraryModel.favorite(it.id) } }
                    NavigationBar(containerColor = MaterialTheme.colorScheme.background, tonalElevation = 0.dp, windowInsets = WindowInsets(0, 0, 0, 0)) {
                        listOf("home" to "Home", "search" to "Search", "library" to "Library").forEach { (route, label) ->
                            NavigationBarItem(selected = destination == route, onClick = { destination = route },
                                icon = { if(route == "search") Icon(Icons.Default.Search, null) else if(route == "home") Icon(Icons.Default.Home, null) else Glyph("queue", null) },
                                label = { Text(label) }, colors = NavigationBarItemDefaults.colors(
                                    selectedIconColor = MaterialTheme.colorScheme.onBackground, selectedTextColor = MaterialTheme.colorScheme.onBackground,
                                    indicatorColor = androidx.compose.ui.graphics.Color.Transparent))
                        }
                    }
                }
            }
        }
        deleteCandidate?.let { song -> AlertDialog(onDismissRequest = { deleteCandidate = null }, title = { Text("Permanently delete audio file?") },
            text = { Text("Delete “${song.title}” from your device and all playlists? This cannot be undone in Still. You may be asked to grant access to its music folder.") },
            confirmButton = { TextButton(onClick = {
                deleteCandidate = null
                if(libraryModel.canDelete(song)) delete(song)
                else { awaitingPermission = song.id; deletionPicker.launch(android.net.Uri.parse(song.root)) }
            }, enabled = !library.scanning && !library.deleting) { Text("Delete file", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { deleteCandidate = null }) { Text("Cancel") } }) }
        library.editing?.let { TagProgressDialog(it, libraryModel) }
        library.message?.let { message -> AlertDialog(onDismissRequest = libraryModel::dismissMessage, title = { Text("Library") }, text = { Text(message) }, confirmButton = { TextButton(onClick = libraryModel::dismissMessage) { Text("OK") } }) }
        playback.error?.let { message -> AlertDialog(onDismissRequest = playbackModel::dismissError, title = { Text("Playback") }, text = { Text(message) }, confirmButton = { TextButton(onClick = playbackModel::dismissError) { Text("OK") } }) }
    }
}
@Composable internal fun Header(title: String, back: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    }
}
@Composable private fun SettingsScreen(state: LibraryState, model: LibraryModel, add: () -> Unit, close: () -> Unit) {
    var recoveryConfirmation by remember { mutableStateOf(false) }
    if (recoveryConfirmation) AlertDialog(onDismissRequest = { recoveryConfirmation = false }, title = { Text("Recover interrupted tag edits?") },
        text = { Text("This restores the retained original audio files for ${state.tagRecoveryCount} interrupted edits. Any changes made to those files since the interruption will be replaced.") },
        confirmButton = { TextButton(onClick = { recoveryConfirmation = false; model.recoverTagEdits() }) { Text("Recover originals") } },
        dismissButton = { TextButton(onClick = { recoveryConfirmation = false }) { Text("Cancel") } })
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
        Header("Settings", close)
        Spacer(Modifier.height(20.dp))
        Text("Appearance", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            listOf(true to "Dark", false to "Light").forEach { (dark, label) ->
                Surface(onClick = { model.theme(dark) }, modifier = Modifier.weight(1f), shape = shape,
                    color = MaterialTheme.colorScheme.surface, border = if(state.dark == dark) androidx.compose.foundation.BorderStroke(1.5.dp, StillBlue) else null) {
                    Row(Modifier.heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Glyph(if(dark) "moon" else "sun", null, tint = StillBlue)
                        Text(label, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                        if(state.dark == dark) Icon(Icons.Default.Check, "Selected", Modifier.size(20.dp), tint = StillBlue)
                    }
                }
            }
        }
        val widgetContext = androidx.compose.ui.platform.LocalContext.current
        val widgetManager = remember(widgetContext) { android.appwidget.AppWidgetManager.getInstance(widgetContext) }
        Spacer(Modifier.height(20.dp)); Text("Listening", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        if (widgetManager.isRequestPinAppWidgetSupported) TextButton(onClick = {
            widgetManager.requestPinAppWidget(android.content.ComponentName(widgetContext, PlaybackWidget::class.java), null, null)
        }) { Text("Add home-screen widget") }
        else Text("Add Still Music from your launcher’s Widgets menu.", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(vertical = 12.dp))
        Text("Browse your library and control playback through Android Auto when your phone is connected.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(20.dp)); Text("Your music", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        Spacer(Modifier.height(12.dp))
        Surface(onClick = add, enabled = !state.scanning && !state.loading && !state.deleting, modifier = Modifier.fillMaxWidth(), shape = shape, color = MaterialTheme.colorScheme.surface) {
            Row(Modifier.heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Default.Add, null, tint = StillBlue); Text("Add music", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (state.tagRecoveryCount > 0) TextButton(onClick = { recoveryConfirmation = true }, enabled = !state.scanning && !state.deleting && state.editing?.running != true) { Text("Recover interrupted edits (${state.tagRecoveryCount})") }
        Spacer(Modifier.height(20.dp)); Text("Lyrics", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        Spacer(Modifier.height(12.dp))
        Surface(shape = shape, color = MaterialTheme.colorScheme.surface) {
            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                    Text("Find lyrics online", fontWeight = FontWeight.SemiBold)
                    Text("Only when no lyrics are available. Results save automatically.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Switch(state.online, model::online)
            }
        }
        Text("When enabled, song title and artist are sent to LRCLIB. Audio stays on your device.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 10.dp, bottom = 24.dp))
    }
}
