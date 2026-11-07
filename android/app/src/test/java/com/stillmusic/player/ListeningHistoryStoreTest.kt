package com.stillmusic.player

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(AudioHostTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class ListeningHistoryStoreTest {
    @Test fun listensSurviveReloadWithoutChangingLibrary() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("still-listening-history", 0).edit().clear().commit()
        val before = LibraryStore(context).read()
        val history = ListeningHistory(context)
        history.record("one")
        history.record("one")
        history.record("two")
        assertEquals(listOf("one", "two"), rankedRepeats(ListeningHistory(context).plays.value, setOf("one", "two"), System.currentTimeMillis()))
        assertEquals(before, LibraryStore(context).read())
    }
}
