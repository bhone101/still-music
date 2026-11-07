package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.IOException

class TagCommitTest {
    @Test fun failedPartialWriteRestoresExactOriginal() {
        val original = File.createTempFile("original", ".mp3").apply { writeBytes(byteArrayOf(1, 2, 3, 4)) }
        val edited = File.createTempFile("edited", ".mp3").apply { writeBytes(byteArrayOf(7, 8, 9)) }
        var destination = original.readBytes()
        var retained = false
        try {
            try {
                commitTagEdit(original, edited, { source ->
                    destination = source.readBytes()
                    if (source == edited) { destination = byteArrayOf(7); throw IOException("Disk full") }
                }, { retained = true })
                fail()
            } catch (_: IOException) { }
            assertArrayEquals(original.readBytes(), destination)
            assertFalse(retained)
        } finally { original.delete(); edited.delete() }
    }
    @Test fun failedRollbackRetainsRecoverableOriginal() {
        val original = File.createTempFile("original", ".flac").apply { writeText("original audio") }
        val edited = File.createTempFile("edited", ".flac")
        var retained = false
        try {
            try { commitTagEdit(original, edited, { throw IOException("Storage disconnected") }, { retained = true }); fail() }
            catch (e: IOException) { assertTrue(e.message!!.contains("Original retained")) }
            assertTrue(retained); assertEquals("original audio", original.readText())
        } finally { original.delete(); edited.delete() }
    }
}
