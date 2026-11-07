package com.stillmusic.player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

object Artwork {
    private val cache = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val missing = object : LruCache<String, Boolean>(512) {}
    private val permits = Semaphore(2)
    private fun key(song: Song, large: Boolean) = "${song.id}:${song.modified}:${song.size}:$large"
    fun peek(song: Song, large: Boolean = false): Bitmap? = cache.get(key(song, large))
    suspend fun load(context: Context, song: Song, large: Boolean = false): Bitmap? = withContext(Dispatchers.IO) {
        val key = key(song, large)
        cache.get(key)?.let { return@withContext it }
        if (missing.get(key) == true) return@withContext null
        val hash = java.security.MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        val disk = java.io.File(context.cacheDir, "covers/$hash.jpg")
        cache.get(key)?.let { return@withContext it }
        if (missing.get(key) == true) return@withContext null
        permits.withPermit {
            cache.get(key)?.let { return@withPermit it }
            if(!large && disk.exists()) BitmapFactory.decodeFile(disk.path)?.let { cache.put(key, it); return@withPermit it }
            val metadata = MediaMetadataRetriever()
            try {
                metadata.setDataSource(context, Uri.parse(song.id))
                val bytes = metadata.embeddedPicture ?: run { missing.put(key, true); return@withPermit null }
                if (bytes.size > 16 * 1024 * 1024) return@withPermit null
                val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                opts.inSampleSize = 1
                while (maxOf(opts.outWidth, opts.outHeight) / opts.inSampleSize > if(large) 768 else 128) opts.inSampleSize *= 2
                opts.inJustDecodeBounds = false
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)?.also { bitmap ->
                    cache.put(key, bitmap)
                    if(!large) runCatching {
                        disk.parentFile?.mkdirs()
                        val atomic = android.util.AtomicFile(disk)
                        val output = atomic.startWrite()
                        try { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output)); atomic.finishWrite(output) }
                        catch(e: Exception) { atomic.failWrite(output); throw e }
                    }
                }
            } catch (_: Exception) { missing.put(key, true); null }
            finally { metadata.release() }
        }
    }
}
