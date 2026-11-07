package com.stillmusic.player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken

/** RemoteViews keeps the home-screen surface lightweight; the service owns playback. */
class PlaybackWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = update(context)
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        if (action !in setOf(PLAY, PREVIOUS, NEXT)) return
        val pending = goAsync()
        val future = MediaController.Builder(context, SessionToken(context, ComponentName(context, PlaybackService::class.java))).buildAsync()
        future.addListener({
            try {
                val controller = future.get()
                when (action) {
                    PLAY -> if (controller.playWhenReady) controller.pause() else { controller.prepare(); controller.play() }
                    PREVIOUS -> if (controller.currentPosition > 3000) controller.seekTo(0) else controller.seekToPreviousMediaItem()
                    NEXT -> controller.seekToNextMediaItem()
                }
            } catch (_: Exception) { /* Opening the app provides the playback error/reconnect flow. */ }
            finally { MediaController.releaseFuture(future); pending.finish() }
        }, context.mainExecutor)
    }
    companion object {
        private const val PLAY = "com.stillmusic.player.widget.PLAY"
        private const val PREVIOUS = "com.stillmusic.player.widget.PREVIOUS"
        private const val NEXT = "com.stillmusic.player.widget.NEXT"
        fun update(context: Context, title: String? = null, artist: String? = null, playing: Boolean? = null) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PlaybackWidget::class.java))
            if (ids.isEmpty()) return
            val prefs = context.getSharedPreferences("widget", Context.MODE_PRIVATE)
            if (playing != null) prefs.edit().putString("title", title).putString("artist", artist).putBoolean("playing", playing).apply()
            val views = RemoteViews(context.packageName, R.layout.playback_widget)
            views.setTextViewText(R.id.widget_title, title ?: prefs.getString("title", null) ?: "Still Music")
            views.setTextViewText(R.id.widget_artist, artist ?: prefs.getString("artist", null) ?: "Choose music in Still")
            val active = playing ?: prefs.getBoolean("playing", false)
            views.setImageViewResource(R.id.widget_play, if (active) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
            views.setContentDescription(R.id.widget_play, if (active) "Pause" else "Play")
            views.setOnClickPendingIntent(R.id.widget_text, PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            listOf(R.id.widget_previous to PREVIOUS, R.id.widget_play to PLAY, R.id.widget_next to NEXT).forEach { (id, action) ->
                views.setOnClickPendingIntent(id, PendingIntent.getBroadcast(context, id, Intent(context, PlaybackWidget::class.java).setAction(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
