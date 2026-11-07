package com.stillmusic.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.isActive

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun PlayerScreen(song: Song?, state: PlaybackState, player: PlaybackModel, online: Boolean, favorite: Boolean, toggleFavorite: () -> Unit, close: () -> Unit, queue: () -> Unit) {
    var lyricsVisible by rememberSaveable { mutableStateOf(false) }
    var timer by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(56.dp)) {
            IconButton(onClick = close, modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp)) { Icon(Icons.Default.KeyboardArrowDown, "Close Now Playing") }
            Text("Now playing", Modifier.align(Alignment.Center), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
        }
        if (song == null) { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Choose a song from your library") }; return }
        BoxWithConstraints(Modifier.weight(1f)) {
            val landscape = maxWidth > maxHeight
            val content: @Composable ColumnScope.() -> Unit = {
                Spacer(Modifier.height(24.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(song.title, Modifier.weight(1f), fontWeight = FontWeight.Bold, fontSize = 24.sp)
                    IconButton(onClick = toggleFavorite) { Icon(if(favorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder, if(favorite) "Remove from Favorites" else "Add to Favorites", tint = if(favorite) StillBlue else MaterialTheme.colorScheme.onSurface) }
                }
                Text(song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 16.sp)
                Spacer(Modifier.height(8.dp))
                Text(song.quality, color = StillBlue, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                var dragging by remember(song.id) { mutableStateOf<Float?>(null) }
                val length = state.duration.coerceAtLeast(song.duration).coerceAtLeast(1)
                Slider(value = dragging ?: (state.position.toFloat()/length).coerceIn(0f,1f), onValueChange = { dragging = it }, onValueChangeFinished = { dragging?.let { player.seek((it * length).toLong()) }; dragging = null }, modifier = Modifier.fillMaxWidth(), enabled = state.duration > 0,
                    thumb = { Box(Modifier.size(14.dp).background(MaterialTheme.colorScheme.onBackground, androidx.compose.foundation.shape.CircleShape)) },
                    track = { slider ->
                        val background = MaterialTheme.colorScheme.outlineVariant
                        val accent = StillBlue
                        androidx.compose.foundation.Canvas(Modifier.fillMaxWidth().height(4.dp)) {
                            drawLine(background, Offset(0f,size.height/2), Offset(size.width,size.height/2), size.height, androidx.compose.ui.graphics.StrokeCap.Round)
                            drawLine(accent, Offset(0f,size.height/2), Offset(size.width*slider.value.coerceIn(0f,1f),size.height/2), size.height, androidx.compose.ui.graphics.StrokeCap.Round)
                        }
                    })
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(durationText(dragging?.let { (it*length).toLong() } ?: state.position), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(durationText(state.duration.coerceAtLeast(song.duration)), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(16.dp))
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                    Control("shuffle", "${state.mode.label}. Tap for ${state.mode.next().label}", player::cycleMode, state.mode == PlayMode.Shuffle)
                    Control("previous", "Previous song", player::previous)
                    FilledIconButton(onClick = player::toggle, modifier = Modifier.size(72.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(containerColor = StillBlue, contentColor = MaterialTheme.colorScheme.onPrimary)) {
                        Glyph(if(state.playing) "pause" else "play", if(state.playing) "Pause" else "Play", Modifier.size(30.dp), tint = MaterialTheme.colorScheme.onPrimary)
                    }
                    Control("next", "Next song", player::next)
                    Control("clock", "Sleep timer", { timer = true }, state.timerRemaining > 0 || state.timerAtEnd)
                }
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                    Control("lyrics", if(lyricsVisible) "Show artwork" else "Show lyrics", { lyricsVisible = !lyricsVisible }, lyricsVisible)
                    Control("queue", "Open queue", queue)
                }
                if(state.timerRemaining > 0 || state.timerAtEnd) Text(if(state.timerAtEnd) "Sleep timer · End of song" else "Sleep timer · ${durationText(state.timerRemaining)}", modifier = Modifier.align(Alignment.CenterHorizontally).padding(bottom = 12.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            }
            if (landscape) Row(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                Box(Modifier.weight(1f).fillMaxHeight().padding(bottom = 16.dp)) { ArtworkLyricsPanel(song.copy(duration = state.duration.takeIf { it > 0 } ?: song.duration), state.position, online, lyricsVisible, player::seek, Modifier.fillMaxSize()) }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), content = content)
            } else Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                Spacer(Modifier.height(16.dp))
                ArtworkLyricsPanel(song.copy(duration = state.duration.takeIf { it > 0 } ?: song.duration), state.position, online, lyricsVisible, player::seek, Modifier.align(Alignment.CenterHorizontally).widthIn(max = 420.dp).fillMaxWidth().aspectRatio(1f))
                content()
            }
        }
    }
    if(timer) SleepTimerSheet(state.timerRemaining, state.timerAtEnd, { timer = false }, { minutes, atEnd -> player.timer(minutes, atEnd); timer = false })
}
@Composable private fun ArtworkLyricsPanel(song: Song, position: Long, online: Boolean, visible: Boolean, seek: (Long) -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val repository = remember { LyricsRepository(context.applicationContext) }
    var lyrics by remember(song.id) { mutableStateOf(Lyrics(emptyList(), false)) }
    var lookupError by remember(song.id) { mutableStateOf<String?>(null) }
    var attempted by remember(song.id) { mutableStateOf(false) }
    var busy by remember(song.id) { mutableStateOf(false) }
    var request by remember(song.id) { mutableIntStateOf(0) }
    var following by remember(song.id) { mutableStateOf(true) }
    val list = rememberLazyListState()
    val active = if(lyrics.synced) LyricParser.activeIndex(lyrics.lines, position) else -1
    LaunchedEffect(song.id, song.lyricUri, song.duration, song.title, song.artist, online, request) {
        busy = true; lookupError = null; attempted = online || request > 0
        try {
            lyrics = resolveLyrics(online || request > 0, { repository.local(song) }, { repository.cached(song) }, { repository.online(song) })
        } catch(e: Exception) { if(e is CancellationException) throw e; lookupError = if(e is LyricsLookupException) e.message else "Couldn’t reach online lyrics. Check your connection and try again." }
        finally { if(kotlinx.coroutines.currentCoroutineContext().isActive) busy = false }
    }
    LaunchedEffect(visible, lyrics) {
        if(visible) following = true
    }
    LaunchedEffect(active, visible, following, lyrics) { if(visible && following && active >= 0) list.scrollToItem((active - 2).coerceAtLeast(0)) }
    Box(modifier.clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surface)) {
        if(!visible) Art(song, Modifier.fillMaxSize(), large = true)
        else Column(Modifier.fillMaxSize().padding(20.dp)) {
            if(busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            if(lyrics.lines.isEmpty()) Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if(busy) "Looking for lyrics…" else lookupError ?: if(attempted) "No matching lyrics found" else "No lyrics yet", textAlign = androidx.compose.ui.text.style.TextAlign.Center, fontWeight = FontWeight.SemiBold)
                if(!busy) TextButton(onClick = { request++ }) { Text("Find online") }
            } else {
                val connection = remember(song.id) { object : NestedScrollConnection { override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset { if(source == NestedScrollSource.UserInput) following = false; return Offset.Zero } } }
                LazyColumn(Modifier.weight(1f).nestedScroll(connection), state = list, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    itemsIndexed(lyrics.lines) { index, line -> Text(line.text.ifBlank { "♪" }, color = if(!lyrics.synced || active == index) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center, fontSize = 20.sp, fontWeight = if(active == index) FontWeight.Bold else FontWeight.Medium,
                        modifier = Modifier.fillMaxWidth().clickable(enabled = lyrics.synced) { seek(line.timeMs); following = true }.padding(vertical = 6.dp)) }
                }
                if(lyrics.synced && !following) TextButton(onClick = { following = true }) { Text("Resume following") }
            }
        }
    }
}
