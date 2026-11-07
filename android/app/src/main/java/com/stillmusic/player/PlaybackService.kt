package com.stillmusic.player

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class PlaybackService : MediaLibraryService() {
    private lateinit var session: MediaLibrarySession
    private lateinit var player: ExoPlayer
    private val handler = Handler(Looper.getMainLooper())
    private var listenSession = ListenSession()
    private val storageExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private lateinit var snapshots: PlaybackSnapshotStore
    private var restored = false
    private var destroyed = false
    private val restoreFuture = com.google.common.util.concurrent.SettableFuture.create<MediaSession.MediaItemsWithStartPosition>()
    private var queueRevision = 0
    private var savedTracks = emptyList<SavedTrack>()
    private var savedOrder = emptyList<Int>()
    private val saveTick = object : Runnable {
        override fun run() {
            savePlayback(false)
            if (player.isPlaying) handler.postDelayed(this, 10_000)
        }
    }
    private fun savePlayback(queueChanged: Boolean) {
        if (!restored) return
        if (queueChanged) {
            savedTracks = (0 until player.mediaItemCount).map { index -> player.getMediaItemAt(index).let {
                SavedTrack(it.mediaId, it.mediaMetadata.title.toString(), it.mediaMetadata.artist.toString(),
                    it.mediaMetadata.albumTitle?.toString().orEmpty(), it.mediaMetadata.extras?.getString("queueKey") ?: java.util.UUID.randomUUID().toString())
            } }
            savedOrder = buildList {
                var index = player.currentTimeline.getFirstWindowIndex(true)
                while (index >= 0 && size < player.mediaItemCount) {
                    add(index)
                    index = player.currentTimeline.getNextWindowIndex(index, Player.REPEAT_MODE_OFF, true)
                }
            }
        }
        val snapshot = PlaybackSnapshot(savedTracks, player.currentMediaItemIndex, player.currentPosition.coerceAtLeast(0), player.shuffleModeEnabled, savedOrder)
        storageExecutor.execute { try { snapshots.write(snapshot) } catch (_: Exception) { /* Keep the previous atomic snapshot. */ } }
    }
    private val listenTick = object : Runnable {
        override fun run() {
            val id = player.currentMediaItem?.mediaId
            if (id != null && listenSession.observe(player.currentPosition, player.duration, player.isPlaying, SystemClock.elapsedRealtime())) {
                ListeningHistory.get(this@PlaybackService).record(id)
            }
            if (player.isPlaying) handler.postDelayed(this, 500)
        }
    }
    private fun clearTimer() {
        handler.removeCallbacks(stopTimer)
        player.pauseAtEndOfMediaItems = false
        session.setSessionExtras(Bundle(session.sessionExtras).apply { remove("timerEnd"); remove("timerAtEnd") })
    }
    private val stopTimer = Runnable { player.pause(); clearTimer() }
    override fun onCreate() {
        super.onCreate()
        player = ExoPlayer.Builder(this, codecRenderers(this))
            .setMediaSourceFactory(androidx.media3.exoplayer.source.DefaultMediaSourceFactory(this, androidx.media3.extractor.ExtractorsFactory { audioExtractors() })).build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_LOCAL)
        }
        val launch = android.app.PendingIntent.getActivity(this, 0, android.content.Intent(this, MainActivity::class.java), android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaLibrarySession.Builder(this, player, object : LibraryCatalog(this, storageExecutor) {
            override fun onPlaybackResumption(session: MediaSession, controller: MediaSession.ControllerInfo): ListenableFuture<MediaSession.MediaItemsWithStartPosition> =
                if (!restored) restoreFuture else Futures.immediateFuture(MediaSession.MediaItemsWithStartPosition(
                    (0 until player.mediaItemCount).map { player.getMediaItemAt(it) }, player.currentMediaItemIndex.coerceAtLeast(0), player.currentPosition.coerceAtLeast(0)))
            override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
                val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
                if (controller.packageName == packageName) {
                    commands.add(SessionCommand(TIMER, Bundle.EMPTY)).add(SessionCommand(MOVE, Bundle.EMPTY)).add(SessionCommand(ENQUEUE, Bundle.EMPTY))
                }
                return MediaSession.ConnectionResult.AcceptedResultBuilder(session).setAvailableSessionCommands(commands.build()).build()
            }
            override fun onCustomCommand(session: MediaSession, controller: MediaSession.ControllerInfo, command: SessionCommand, args: Bundle): ListenableFuture<SessionResult> {
                if(command.customAction == ENQUEUE) {
                    val uri = args.getString("uri") ?: return Futures.immediateFuture(SessionResult(androidx.media3.session.SessionError.ERROR_BAD_VALUE))
                    if(android.net.Uri.parse(uri).scheme != "content") return Futures.immediateFuture(SessionResult(androidx.media3.session.SessionError.ERROR_BAD_VALUE))
                    val order = mutableListOf<Int>()
                    val timeline = player.currentTimeline
                    var index = timeline.getFirstWindowIndex(player.shuffleModeEnabled)
                    while(index >= 0 && order.size < player.mediaItemCount) {
                        order.add(index)
                        index = timeline.getNextWindowIndex(index, Player.REPEAT_MODE_OFF, player.shuffleModeEnabled)
                    }
                    val newIndex = player.mediaItemCount
                    val desired = queueWithAddition(order, player.currentMediaItemIndex, newIndex, args.getBoolean("next"))
                    val item = androidx.media3.common.MediaItem.Builder().setMediaId(uri).setUri(uri).setMediaMetadata(
                        androidx.media3.common.MediaMetadata.Builder().setTitle(args.getString("title")).setArtist(args.getString("artist")).setAlbumTitle(args.getString("album"))
                            .setExtras(Bundle().apply { putString("queueKey", java.util.UUID.randomUUID().toString()) }).build()).build()
                    if(newIndex == 0) player.playWhenReady = false
                    player.addMediaItem(item)
                    if(player.shuffleModeEnabled) player.setShuffleOrder(androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder(desired.toIntArray(), SystemClock.elapsedRealtime()))
                    else if(args.getBoolean("next")) player.moveMediaItem(newIndex, desired.indexOf(newIndex))
                    if(newIndex == 0) player.prepare()
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
                if(command.customAction == MOVE) {
                    val fromKey = args.getString("from")
                    val toKey = args.getString("to")
                    val timeline = player.currentTimeline
                    val order = mutableListOf<Int>()
                    var index = timeline.getFirstWindowIndex(player.shuffleModeEnabled)
                    while(index >= 0 && order.size < player.mediaItemCount) {
                        order.add(index)
                        index = timeline.getNextWindowIndex(index, Player.REPEAT_MODE_OFF, player.shuffleModeEnabled)
                    }
                    val from = order.indexOfFirst { player.getMediaItemAt(it).mediaMetadata.extras?.getString("queueKey") == fromKey }
                    val to = order.indexOfFirst { player.getMediaItemAt(it).mediaMetadata.extras?.getString("queueKey") == toKey }
                    if(from >= 0 && to >= 0) {
                        if(player.shuffleModeEnabled) {
                            player.setShuffleOrder(androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder(movedQueue(order, from, to).toIntArray(), SystemClock.elapsedRealtime()))
                        } else player.moveMediaItem(order[from], order[to])
                    }
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
                if (command.customAction != TIMER) return Futures.immediateFuture(SessionResult(androidx.media3.session.SessionError.ERROR_NOT_SUPPORTED))
                val minutes = args.getInt("minutes").coerceIn(0, 1440)
                clearTimer()
                val atEnd = args.getBoolean("atEnd") && player.currentMediaItem != null
                player.pauseAtEndOfMediaItems = atEnd
                if (!atEnd && minutes > 0) handler.postDelayed(stopTimer, minutes * 60_000L)
                session.setSessionExtras(Bundle(session.sessionExtras).apply { putBoolean("timerAtEnd", atEnd); putLong("timerEnd", if (!atEnd && minutes > 0) SystemClock.elapsedRealtime() + minutes * 60_000L else 0) })
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
        }).setSessionActivity(launch).build()
        player.addListener(object : Player.Listener {
            override fun onEvents(player: Player, events: Player.Events) {
                val changed = events.contains(Player.EVENT_TIMELINE_CHANGED) || events.contains(Player.EVENT_SHUFFLE_MODE_ENABLED_CHANGED)
                if (changed) queueRevision++
                if (changed || events.contains(Player.EVENT_POSITION_DISCONTINUITY) || events.contains(Player.EVENT_PLAY_WHEN_READY_CHANGED)) savePlayback(changed)
                if (events.contains(Player.EVENT_MEDIA_METADATA_CHANGED) || events.contains(Player.EVENT_IS_PLAYING_CHANGED) || changed) PlaybackWidget.update(this@PlaybackService, player.mediaMetadata.title?.toString(), player.mediaMetadata.artist?.toString(), player.isPlaying)
            }
            override fun onMediaItemTransition(mediaItem: androidx.media3.common.MediaItem?, reason: Int) {
                listenSession = ListenSession()
            }
            override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
                if (reason == Player.DISCONTINUITY_REASON_SEEK && oldPosition.positionMs >= player.duration - 50 && newPosition.positionMs == 0L) {
                    listenSession = ListenSession()
                } else listenSession.interrupt()
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                listenSession.interrupt()
                handler.removeCallbacks(listenTick)
                if (isPlaying) handler.post(listenTick)
                handler.removeCallbacks(saveTick)
                if (isPlaying) handler.postDelayed(saveTick, 10_000)
            }

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                if(reason == Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM && session.sessionExtras.getBoolean("timerAtEnd")) clearTimer()
            }
            override fun onPlaybackStateChanged(playbackState: Int) {
                if(playbackState == Player.STATE_ENDED && session.sessionExtras.getBoolean("timerAtEnd")) { player.pause(); clearTimer() }
            }
            override fun onTracksChanged(tracks: Tracks) {
                if (!tracks.isEmpty && !tracks.isTypeSelected(C.TRACK_TYPE_AUDIO)) {
                    player.pause()
                    session.setSessionExtras(Bundle(session.sessionExtras).apply { putString("audioError", "No playable audio track was found in this file.") })
                } else if (tracks.isTypeSelected(C.TRACK_TYPE_AUDIO)) {
                    session.setSessionExtras(Bundle(session.sessionExtras).apply { remove("audioError") })
                }
            }
        })
        snapshots = PlaybackSnapshotStore(this)
        val revision = queueRevision
        storageExecutor.execute {
            val saved = snapshots.read()
            handler.post {
                if (destroyed) return@post
                if (queueRevision == revision && player.mediaItemCount == 0 && saved != null && saved.tracks.isNotEmpty()) {
                    player.setMediaItems(saved.tracks.map { it.mediaItem() }, saved.index, saved.position)
                    player.setShuffleOrder(androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder(saved.order.toIntArray(), SystemClock.elapsedRealtime()))
                    player.shuffleModeEnabled = saved.shuffle
                    player.playWhenReady = false
                    player.prepare()
                }
                restored = true
                restoreFuture.set(MediaSession.MediaItemsWithStartPosition((0 until player.mediaItemCount).map { player.getMediaItemAt(it) }, player.currentMediaItemIndex.coerceAtLeast(0), player.currentPosition.coerceAtLeast(0)))
                savePlayback(true)
            }
        }
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? =
        if (controllerInfo.packageName == packageName || controllerInfo.isTrusted ||
            (controllerInfo.packageName == "com.google.android.projection.gearhead" && packageManager.getPackagesForUid(controllerInfo.uid)?.contains(controllerInfo.packageName) == true)) session else null
    override fun onDestroy() {
        destroyed = true
        savePlayback(true)
        PlaybackWidget.update(this, player.mediaMetadata.title?.toString(), player.mediaMetadata.artist?.toString(), false)
        storageExecutor.shutdown()
        handler.removeCallbacksAndMessages(null)
        session.release(); player.release()
        super.onDestroy()
    }
    companion object { const val TIMER = "still.sleepTimer"; const val MOVE = "still.moveQueue"; const val ENQUEUE = "still.enqueue" }
}
