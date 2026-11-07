package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(AudioHostTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class PlaybackSnapshotTest {
    @Test fun duplicateSongsShuffleOrderAndPositionSurviveRestart() {
        val context = RuntimeEnvironment.getApplication()
        val a = SavedTrack("content://music/a", "A", "Artist", "Album", "first")
        val snapshot = PlaybackSnapshot(listOf(a, a.copy(key = "second"), a.copy(id = "content://music/b", key = "third")), 1, 15243, true, listOf(2, 0, 1))
        PlaybackSnapshotStore(context).write(snapshot)
        assertEquals(snapshot, PlaybackSnapshotStore(context).read())
        assertEquals("second", PlaybackSnapshotStore(context).read()!!.tracks[1].mediaItem().mediaMetadata.extras!!.getString("queueKey"))
    }
    @Test fun emptyQueueDoesNotResurrectOldSongs() {
        val store = PlaybackSnapshotStore(RuntimeEnvironment.getApplication())
        store.write(PlaybackSnapshot(listOf(SavedTrack("content://music/a", "A", "B", "C", "key")), 0, 100, false, listOf(0)))
        store.write(PlaybackSnapshot(emptyList(), 0, 0, false, emptyList()))
        assertTrue(store.read()!!.tracks.isEmpty())
    }
    @Test fun invalidShufflePermutationIsRejected() {
        val store = PlaybackSnapshotStore(RuntimeEnvironment.getApplication())
        store.write(PlaybackSnapshot(listOf(SavedTrack("content://music/a", "A", "B", "C", "key")), 0, 100, true, listOf(8)))
        assertNull(store.read())
    }
}
