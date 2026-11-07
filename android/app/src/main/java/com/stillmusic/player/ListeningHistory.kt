package com.stillmusic.player

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

internal const val REPEAT_WINDOW_MS = 30L * 24 * 60 * 60 * 1000
data class Listen(val id: String, val at: Long)

internal fun rankedRepeats(plays: List<Listen>, available: Set<String>, now: Long): List<String> =
    plays.filter { it.id in available && it.at > now - REPEAT_WINDOW_MS && it.at <= now }
        .groupBy { it.id }.entries
        .sortedWith(compareByDescending<Map.Entry<String, List<Listen>>> { it.value.size }
            .thenByDescending { it.value.maxOf { play -> play.at } }.thenBy { it.key })
        .take(30).map { it.key }

/** Counts actual playback progress once per queue occurrence. Pauses and seeks add no time. */
internal class ListenSession {
    private var listened = 0L
    private var counted = false
    private var position: Long? = null
    private var uptime = 0L
    fun interrupt() { position = null }
    fun observe(at: Long, duration: Long, playing: Boolean, now: Long): Boolean {
        if (!playing || duration <= 0) { interrupt(); return false }
        val previous = position
        val elapsed = now - uptime
        position = at
        uptime = now
        if (counted || previous == null) return false
        val progress = at - previous
        if (elapsed !in 1..1999 || progress <= 0 || progress > elapsed + 500) return false
        listened += minOf(progress, elapsed)
        if (listened >= minOf(30_000, duration / 2)) { counted = true; return true }
        return false
    }
}

/** Shared by the playback service and UI; history stays separate from library writes. */
class ListeningHistory internal constructor(context: Context) {
    private val preferences = context.getSharedPreferences("still-listening-history", Context.MODE_PRIVATE)
    private val mutable = MutableStateFlow(read())
    val plays = mutable.asStateFlow()
    private fun read(): List<Listen> = try {
        val array = JSONArray(preferences.getString("plays", "[]"))
        val now = System.currentTimeMillis()
        (0 until array.length()).map { array.getJSONObject(it).let { o -> Listen(o.getString("id"), o.getLong("at")) } }
            .filter { it.at > now - REPEAT_WINDOW_MS && it.at <= now }
    } catch (_: Exception) { emptyList() }
    fun record(id: String, now: Long = System.currentTimeMillis()) {
        val recent = mutable.value.filter { it.at > now - REPEAT_WINDOW_MS && it.at <= now } + Listen(id, now)
        preferences.edit().putString("plays", JSONArray(recent.map { JSONObject().put("id", it.id).put("at", it.at) }).toString()).apply()
        mutable.value = recent
    }
    companion object {
        @Volatile private var instance: ListeningHistory? = null
        fun get(context: Context): ListeningHistory = instance ?: synchronized(this) {
            instance ?: ListeningHistory(context.applicationContext).also { instance = it }
        }
    }
}
