package com.stillmusic.player

import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable fun Art(song: Song?, modifier: Modifier = Modifier, large: Boolean = false) {
    val context = LocalContext.current
    val bitmap by key(song?.id, song?.modified, large) { produceState<android.graphics.Bitmap?>(song?.let { Artwork.peek(it, large) }, song?.id, song?.modified, large) { value = song?.let { Artwork.peek(it, large) }; value = song?.let { Artwork.load(context, it, large) } } }
    Box(modifier.clip(RoundedCornerShape(10.dp)).background(Brush.linearGradient(listOf(Color(0xFF293346), Color(0xFF5277B8)))), contentAlignment = Alignment.Center) {
        bitmap?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
    }
}
@Composable fun Glyph(kind: String, description: String?, modifier: Modifier = Modifier, tint: Color = MaterialTheme.colorScheme.onBackground) {
    Canvas(modifier.size(22.dp).then(if (description != null) Modifier.semantics { contentDescription = description } else Modifier)) {
        val s = size.width / 24f
        fun line(x: Float, y: Float, a: Float, b: Float) = drawLine(tint, Offset(x*s,y*s),Offset(a*s,b*s),2*s,StrokeCap.Round)
        fun triangle(x: Float, reverse: Boolean = false) {
            val p = Path().apply { moveTo(x*s,5*s); lineTo((x+if(reverse) -10 else 10)*s,12*s); lineTo(x*s,19*s); close() }; drawPath(p,tint)
        }
        when(kind) {
            "play" -> triangle(8f)
            "pause" -> { drawRect(tint,Offset(7*s,5*s),androidx.compose.ui.geometry.Size(3*s,14*s));drawRect(tint,Offset(14*s,5*s),androidx.compose.ui.geometry.Size(3*s,14*s)) }
            "next" -> { triangle(5f);line(18f,5f,18f,19f) }
            "previous" -> { triangle(19f,true);line(6f,5f,6f,19f) }
            "moon" -> {
                val path = Path().apply { moveTo(15*s,3*s); cubicTo(4*s,2*s,0*s,16*s,10*s,21*s); cubicTo(16*s,24*s,22*s,18*s,21*s,14*s); cubicTo(13*s,19*s,8*s,10*s,15*s,3*s) }
                drawPath(path,tint,style=Stroke(1.7f*s))
            }
            "sun" -> {
                drawCircle(tint,4*s,style=Stroke(1.7f*s))
                for(i in 0..7) { val a = i * kotlin.math.PI / 4; line(12f+8f*kotlin.math.cos(a).toFloat(),12f+8f*kotlin.math.sin(a).toFloat(),12f+10f*kotlin.math.cos(a).toFloat(),12f+10f*kotlin.math.sin(a).toFloat()) }
            }
            "clock" -> {drawCircle(tint,9*s,style=Stroke(1.8f*s));line(12f,6f,12f,12f);line(12f,12f,16f,14f)}
            "art" -> {drawRoundRect(tint,Offset(3*s,3*s),androidx.compose.ui.geometry.Size(18*s,18*s),androidx.compose.ui.geometry.CornerRadius(3*s),style=Stroke(1.8f*s));drawCircle(tint,4*s,style=Stroke(1.8f*s))}
            "lyrics", "queue" -> {line(4f,6f,20f,6f);line(4f,12f,17f,12f);line(4f,18f,13f,18f)}
            "normal" -> { line(4f,12f,20f,12f); line(15f,7f,20f,12f); line(15f,17f,20f,12f) }
            "shuffle" -> {line(4f,6f,8f,6f);line(8f,6f,16f,18f);line(16f,18f,21f,18f);line(4f,18f,8f,18f);line(8f,18f,16f,6f);line(16f,6f,21f,6f);line(18f,3f,21f,6f);line(18f,9f,21f,6f)}
            else -> {
                line(4f,10f,4f,6f); line(4f,6f,20f,6f); line(20f,6f,17f,3f)
                line(20f,14f,20f,18f); line(20f,18f,4f,18f); line(4f,18f,7f,21f)
                if(kind == "repeat-one") { line(11f,10f,13f,9f); line(13f,9f,13f,15f) }
            }
        }
    }
}
@Composable fun Control(kind: String, label: String, action: () -> Unit, selected: Boolean = false, enabled: Boolean = true) {
    IconButton(onClick = action, enabled = enabled, modifier = Modifier.size(48.dp)) { Glyph(kind, label, tint = if (selected) StillBlue else MaterialTheme.colorScheme.onBackground.copy(alpha = if (enabled) 1f else .4f)) }
}
@Composable fun MiniPlayer(song: Song?, state: PlaybackState, open: () -> Unit, play: () -> Unit, favorite: Boolean, toggleFavorite: () -> Unit) {
    if (song == null) return
    Surface(Modifier.padding(horizontal = 8.dp, vertical = 2.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable(onClick = open), color = MaterialTheme.colorScheme.surface) {
        Column {
            Row(Modifier.padding(start = 8.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Art(song, Modifier.size(40.dp))
                Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                    Text(song.title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(song.artist, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconButton(onClick = toggleFavorite) { Icon(if(favorite) androidx.compose.material.icons.Icons.Default.Favorite else androidx.compose.material.icons.Icons.Default.FavoriteBorder, if(favorite) "Remove from Favorites" else "Add to Favorites", tint = if(favorite) StillBlue else MaterialTheme.colorScheme.onSurface) }
                IconButton(onClick = play, modifier = Modifier.size(48.dp)) {
                    Glyph(if(state.playing) "pause" else "play", if(state.playing) "Pause" else "Play", Modifier.size(20.dp))
                }
            }
            LinearProgressIndicator(progress = { if (state.duration > 0) (state.position.toFloat()/state.duration).coerceIn(0f,1f) else 0f }, modifier = Modifier.fillMaxWidth().height(2.dp), color = StillBlue, trackColor = MaterialTheme.colorScheme.outlineVariant)
        }
    }
}

@Composable fun MusicSearch(value: String, change: (String) -> Unit, modifier: Modifier = Modifier, compact: Boolean = false) {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    TextField(value = value, onValueChange = change, modifier = modifier.heightIn(min = 56.dp), singleLine = true,
        placeholder = { Text("Songs, artists, albums") },
        leadingIcon = { Icon(androidx.compose.material.icons.Icons.Default.Search, null) },
        trailingIcon = { if(value.isNotEmpty()) IconButton(onClick = { change("") }) { Text("×", fontSize = 24.sp, modifier = Modifier.semantics { contentDescription = "Clear search" }) } },
        shape = RoundedCornerShape(14.dp),
        colors = TextFieldDefaults.colors(focusedContainerColor = MaterialTheme.colorScheme.surface, unfocusedContainerColor = MaterialTheme.colorScheme.surface,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search),
        keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { focus.clearFocus() }))
}
