package com.stillmusic.player

import android.app.Application
import android.content.ComponentName
import android.os.Bundle
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class QueueItem(val index: Int, val id: String, val title: String, val artist: String, val key: String)
data class PlaybackState(val connected: Boolean = false, val id: String? = null, val playing: Boolean = false, val position: Long = 0,
    val duration: Long = 0, val mode: PlayMode = PlayMode.Normal, val queue: List<QueueItem> = emptyList(), val currentIndex: Int = -1,
    val error: String? = null, val timerRemaining: Long = 0, val timerAtEnd: Boolean = false)
class PlaybackModel(app: Application) : AndroidViewModel(app) {
    private val mutable = MutableStateFlow(PlaybackState())
    val state = mutable.asStateFlow()
    private var controller: MediaController? = null
    private var observedAudioError: String? = null
    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) = refresh(
            events.contains(Player.EVENT_TIMELINE_CHANGED) || events.contains(Player.EVENT_SHUFFLE_MODE_ENABLED_CHANGED) || events.contains(Player.EVENT_MEDIA_METADATA_CHANGED))
        override fun onPlayerError(error: PlaybackException) {
            mutable.value = mutable.value.copy(error = "This file could not be played (${error.errorCodeName}). Try another file or reconnect its storage.")
        }
    }
    private val future = MediaController.Builder(app, SessionToken(app, ComponentName(app, PlaybackService::class.java)))
        .setListener(object : MediaController.Listener {
            override fun onDisconnected(controller: MediaController) { mutable.value = mutable.value.copy(connected = false, playing = false, error = "Playback service disconnected. Reopen the app to reconnect.") }
            override fun onExtrasChanged(controller: MediaController, extras: Bundle) { refresh(false) }
        }).buildAsync()
    init { future.addListener({
        try { controller = future.get(); controller?.addListener(listener); refresh() }
        catch (_: Exception) { mutable.value = mutable.value.copy(error = "Playback could not start. Please reopen the app.") }
    }, app.mainExecutor) }
    fun refresh(rebuildQueue: Boolean = true) {
        val p = controller ?: return
        val queue = if (!rebuildQueue) mutable.value.queue else buildList {
            val timeline = p.currentTimeline
            var index = timeline.getFirstWindowIndex(p.shuffleModeEnabled)
            val seen = hashSetOf<Int>()
            while (index >= 0 && index < p.mediaItemCount && seen.add(index)) {
                val item = p.getMediaItemAt(index)
                add(QueueItem(index, item.mediaId, item.mediaMetadata.title?.toString().orEmpty(), item.mediaMetadata.artist?.toString().orEmpty(), item.mediaMetadata.extras?.getString("queueKey") ?: "$index:${item.mediaId}"))
                index = timeline.getNextWindowIndex(index, Player.REPEAT_MODE_OFF, p.shuffleModeEnabled)
            }
        }
        val audioError = p.sessionExtras.getString("audioError")
        val newAudioError = audioError?.takeIf { it != observedAudioError }
        observedAudioError = audioError
        mutable.value = mutable.value.copy(connected = true, id = p.currentMediaItem?.mediaId, playing = p.isPlaying,
            position = p.currentPosition.coerceAtLeast(0), duration = p.duration.coerceAtLeast(0), queue = queue, currentIndex = p.currentMediaItemIndex,
            mode = when { p.shuffleModeEnabled -> PlayMode.Shuffle; else -> PlayMode.Normal },
            timerAtEnd = p.sessionExtras.getBoolean("timerAtEnd"), timerRemaining = (p.sessionExtras.getLong("timerEnd") - SystemClock.elapsedRealtime()).coerceAtLeast(0),
            error = newAudioError ?: mutable.value.error)
    }
    fun tick() {
        val p = controller ?: return
        mutable.value = mutable.value.copy(position = p.currentPosition.coerceAtLeast(0), duration = p.duration.coerceAtLeast(0),
            timerAtEnd = p.sessionExtras.getBoolean("timerAtEnd"), timerRemaining = (p.sessionExtras.getLong("timerEnd") - SystemClock.elapsedRealtime()).coerceAtLeast(0))
    }
    fun play(songs: List<Song>, id: String) {
        val index = songs.indexOfFirst { it.id == id }; if (index < 0) return
        controller?.run {
            setMediaItems(songs.map { MediaItem.Builder().setMediaId(it.id).setUri(it.id).setMediaMetadata(
                MediaMetadata.Builder().setTitle(it.title).setArtist(it.artist).setAlbumTitle(it.album).setExtras(Bundle().apply { putString("queueKey", java.util.UUID.randomUUID().toString()) }).build()).build() }, index, 0)
            prepare(); play()
            mutable.value = mutable.value.copy(error = null)
        }
    }
    fun enqueue(song: Song, next: Boolean) {
        controller?.sendCustomCommand(SessionCommand(PlaybackService.ENQUEUE, Bundle.EMPTY), Bundle().apply {
            putString("uri", song.id); putString("title", song.title); putString("artist", song.artist); putString("album", song.album); putBoolean("next", next)
        })
    }
    fun enqueue(songs: List<Song>, next: Boolean) {
        // Play-next inserts immediately after the current song each time.
        batchQueueCommands(songs, next, state.value.queue.isEmpty()).forEach { (song, insertNext) -> enqueue(song, insertNext) }
    }

    fun toggle() { controller?.run {
        if (isPlaying || (playWhenReady && playbackState == Player.STATE_BUFFERING)) pause()
        else { if (playbackState == Player.STATE_ENDED) seekTo(0); if (playbackState == Player.STATE_IDLE) prepare(); mutable.value = mutable.value.copy(error = null); play() }
    } }
    fun next() { controller?.seekToNextMediaItem() }
    fun previous() { controller?.run { if (currentPosition > 3000) seekTo(0) else seekToPreviousMediaItem() } }
    fun seek(ms: Long) { controller?.seekTo(ms.coerceAtLeast(0)) }
    fun jump(index: Int) { controller?.run { seekTo(index, 0); play() } }
    fun remove(index: Int) { controller?.removeMediaItem(index) }
    fun move(from: Int, to: Int) { controller?.run {
        if(from !in 0 until mediaItemCount || to !in 0 until mediaItemCount) return@run
        sendCustomCommand(SessionCommand(PlaybackService.MOVE, Bundle.EMPTY), Bundle().apply {
            putString("from", getMediaItemAt(from).mediaMetadata.extras?.getString("queueKey"))
            putString("to", getMediaItemAt(to).mediaMetadata.extras?.getString("queueKey"))
        })
    } }

    fun pauseForTagEditing(ids: Set<String>) { controller?.run { if (currentMediaItem?.mediaId in ids) { pause(); stop() } } }
    fun pauseForDeletion(id: String) { controller?.run { if(currentMediaItem?.mediaId == id) pause() } }
    fun removeSong(id: String) { controller?.run { for(index in mediaItemCount-1 downTo 0) if(getMediaItemAt(index).mediaId == id) removeMediaItem(index) } }
    fun cycleMode() { controller?.run {
        val next = mutable.value.mode.next()
        shuffleModeEnabled = next == PlayMode.Shuffle
        repeatMode = Player.REPEAT_MODE_OFF
        refresh()
    } }
    fun timer(minutes: Int, atEnd: Boolean = false) { controller?.sendCustomCommand(SessionCommand(PlaybackService.TIMER, Bundle.EMPTY), Bundle().apply { putInt("minutes", minutes); putBoolean("atEnd", atEnd) }) }
    fun dismissError() { mutable.value = mutable.value.copy(error = null) }
    override fun onCleared() { controller?.removeListener(listener); MediaController.releaseFuture(future); super.onCleared() }
}
