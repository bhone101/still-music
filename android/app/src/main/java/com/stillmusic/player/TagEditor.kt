package com.stillmusic.player

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

data class TagEditProgress(val total: Int, val completed: Int = 0, val updated: Int = 0, val failures: List<String> = emptyList(), val running: Boolean = true, val cancelling: Boolean = false, val recovering: Boolean = false)

@Composable internal fun TagEditor(songs: List<Song>, model: LibraryModel, playback: PlaybackModel, close: () -> Unit) {
    val fields = remember { linkedMapOf("TITLE" to "Title", "ARTIST" to "Artist", "ALBUM" to "Album", "ALBUMARTIST" to "Album artist", "GENRE" to "Genre") }
    val originals = remember(songs) { mapOf("TITLE" to songs.map { it.title }, "ARTIST" to songs.map { it.artist },
        "ALBUM" to songs.map { it.album }, "ALBUMARTIST" to songs.map { it.albumArtist }, "GENRE" to songs.map { it.genre }) }
    val values = remember(songs) { mutableStateMapOf<String, String>().apply {
        originals.forEach { (key, entries) -> put(key, entries.distinct().singleOrNull().orEmpty()) }
    } }
    val enabled = remember { mutableStateMapOf<String, Boolean>() }
    val supported = songs.filter { it.format.lowercase() in setOf("mp3", "flac") }
    var pending by remember { mutableStateOf<TagChanges?>(null) }
    var awaiting by remember { mutableStateOf<Song?>(null) }
    var permissionStep by remember { mutableIntStateOf(0) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        val song = awaiting
        awaiting = null
        if (uri == null || song == null || !model.grantEditing(song, uri)) pending = null else permissionStep++
    }
    LaunchedEffect(pending, permissionStep) {
        val changes = pending ?: return@LaunchedEffect
        val missing = supported.firstOrNull { !model.canDelete(it) }
        if (missing != null) { awaiting = missing; picker.launch(android.net.Uri.parse(missing.root)) }
        else { playback.pauseForTagEditing(supported.map { it.id }.toSet()); model.editTags(supported, changes); close() }
    }
    AlertDialog(onDismissRequest = { if (pending == null) close() }, title = { Text(if (songs.size == 1) "Edit song tags" else "Edit ${songs.size} songs") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Checked fields will be written to every selected audio file. Unchecked fields stay unchanged. An empty checked field clears that tag.", style = MaterialTheme.typography.bodySmall)
            if (supported.size != songs.size) Text("${songs.size - supported.size} unsupported files will be skipped. Editing currently supports MP3 and FLAC.", modifier = Modifier.padding(vertical = 12.dp), color = MaterialTheme.colorScheme.error)
            fields.forEach { (key, label) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(enabled[key] == true, { enabled[key] = it }, enabled = pending == null)
                    OutlinedTextField(values[key].orEmpty(), { values[key] = it.take(1000); enabled[key] = true },
                        label = { Text(label) }, placeholder = { if (originals.getValue(key).distinct().size > 1) Text("Multiple values") }, enabled = pending == null, singleLine = true, modifier = Modifier.weight(1f).padding(vertical = 4.dp))
                }
            }
            Text("Editing the current song pauses playback. Android may ask for write access to each music folder.", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 12.dp))
        }
    }, confirmButton = { TextButton(enabled = supported.isNotEmpty() && enabled.values.any { it } && pending == null,
        onClick = { pending = TagChanges(values.filterKeys { enabled[it] == true }) }) { Text("Save tags") } },
        dismissButton = { TextButton(onClick = close, enabled = pending == null) { Text("Cancel") } })
}

@Composable internal fun TagProgressDialog(progress: TagEditProgress, model: LibraryModel) {
    AlertDialog(onDismissRequest = { if (!progress.running) model.dismissTagProgress() }, title = {
        Text(if (progress.recovering) "Recovering original files" else if (progress.running) "Updating ${minOf(progress.completed + 1, progress.total)} of ${progress.total} songs" else "Tag editing complete")
    }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (progress.recovering) LinearProgressIndicator(Modifier.fillMaxWidth())
            else if (progress.running) LinearProgressIndicator(progress = { progress.completed.toFloat() / progress.total.coerceAtLeast(1) }, modifier = Modifier.fillMaxWidth())
            if (!progress.recovering) Text("${progress.updated} updated · ${progress.failures.size} failed · ${progress.total - progress.completed} remaining")
            if (progress.cancelling) Text("${if (progress.running) "Stopping after the current file." else "Cancelled. Unprocessed files were kept."}")
            progress.failures.forEach { Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp)) }
        }
    }, confirmButton = {
        TextButton(onClick = { if (progress.running) model.cancelTagEditing() else model.dismissTagProgress() }, enabled = !progress.recovering && (!progress.running || !progress.cancelling)) {
            Text(if (progress.recovering) "Recovering…" else if (progress.running) "Cancel after this file" else "Done")
        }
    })
}
