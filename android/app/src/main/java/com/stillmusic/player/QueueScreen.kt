package com.stillmusic.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.delay

@Composable internal fun QueueScreen(state: PlaybackState, player: PlaybackModel, songs: List<Song>, close: () -> Unit) {
    val songsById = remember(songs) { songs.associateBy { it.id } }
    val list = rememberLazyListState()
    var dragging by remember { mutableStateOf<String?>(null) }
    var dragY by remember { mutableFloatStateOf(0f) }
    var startY by remember { mutableFloatStateOf(0f) }
    var target by remember { mutableIntStateOf(-1) }
    val latestQueue by rememberUpdatedState(state.queue)
    fun updateTarget() {
        val center = startY + dragY
        list.layoutInfo.visibleItemsInfo.firstOrNull { center >= it.offset && center < it.offset + it.size }?.let { target = it.index }
    }
    LaunchedEffect(state.queue.map { it.key }) { dragging = null }
    LaunchedEffect(dragging) {
        while(dragging != null) {
            val center = startY + dragY
            val info = list.layoutInfo
            val speed = when { center < info.viewportStartOffset + 80 -> -18f; center > info.viewportEndOffset - 80 -> 18f; else -> 0f }
            if(speed != 0f) { list.scrollBy(speed); updateTarget() }
            delay(16)
        }
    }
    Column(Modifier.fillMaxSize()) {
        Header("Queue", close)
        Text("${state.queue.size} songs · Hold a handle to reorder", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        if(state.queue.isEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("The queue is empty") }
        LazyColumn(state = list) { itemsIndexed(state.queue, key = { _, item -> item.key }) { rowIndex, item ->
            val active = dragging == item.key
            val row = list.layoutInfo.visibleItemsInfo.firstOrNull { it.key == item.key }
            Row(Modifier.fillMaxWidth().zIndex(if(active) 1f else 0f)
                .graphicsLayer { translationY = if(active && row != null) startY + dragY - row.offset - row.size / 2f else 0f }
                .background(if(active || (dragging != null && target == rowIndex)) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.background)
                .clickable { player.jump(item.index) }.padding(start = 20.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Art(songsById[item.id], Modifier.size(48.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    if(item.index == state.currentIndex) Text("Now playing", style = MaterialTheme.typography.labelSmall, color = StillBlue)
                    else if(rowIndex == state.queue.indexOfFirst { it.index == state.currentIndex } + 1) Text("Up next", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(item.title, color = if(item.index == state.currentIndex) StillBlue else MaterialTheme.colorScheme.onBackground, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(item.artist, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Box(Modifier.size(48.dp).semantics {
                    customActions = listOf(CustomAccessibilityAction("Move up") { if(rowIndex > 0) player.move(item.index, state.queue[rowIndex-1].index); true },
                        CustomAccessibilityAction("Move down") { if(rowIndex < state.queue.lastIndex) player.move(item.index, state.queue[rowIndex+1].index); true })
                }.pointerInput(item.key) {
                    detectDragGesturesAfterLongPress(onDragStart = {
                        list.layoutInfo.visibleItemsInfo.firstOrNull { it.key == item.key }?.let { visible ->
                            startY = visible.offset + visible.size / 2f; dragY = 0f; target = visible.index; dragging = item.key
                        }
                    }, onDrag = { change, amount -> change.consume(); dragY += amount.y; updateTarget() },
                        onDragCancel = { dragging = null }, onDragEnd = {
                            val from = latestQueue.firstOrNull { it.key == dragging }?.index
                            val to = latestQueue.getOrNull(target)?.index
                            if(from != null && to != null) player.move(from, to)
                            dragging = null
                        })
                }, contentAlignment = Alignment.Center) { Glyph("queue", "Drag ${item.title} to reorder") }
                IconButton(onClick = { player.remove(item.index) }) { Icon(Icons.Default.Close, "Remove ${item.title} from queue") }
            }
        } }
    }
}
