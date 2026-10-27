package com.mmfreitas.aibrief.core

import kotlinx.coroutines.runBlocking
import kotlin.io.path.createTempDirectory
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import java.time.Instant

private fun at(minute: Int): Instant = Instant.parse("2026-10-27T12:00:00Z").plusSeconds(60L * minute)

private fun saved(id: String, savedMin: Int, updatedMin: Int? = null, note: String = "") = SavedItem(
    item = BriefItem.make("https://example.com/$id", id, "", SourceKind.blog, "Blog", "", 1.0),
    savedAt = at(savedMin), note = note, updatedAt = updatedMin?.let(::at),
)

class MergeTest {
    @Test fun newestCopyWins() {
        val local = SyncSnapshot(listOf(saved("a", 0, 5, note = "local")))
        val remote = SyncSnapshot(listOf(saved("a", 0, 7, note = "remote")))
        assertEquals("remote", CollectionSync.merge(local, remote).items.single().note)
        assertEquals("remote", CollectionSync.merge(remote, local).items.single().note)
    }

    @Test fun unionOrderedNewestSavedFirst() {
        val merged = CollectionSync.merge(SyncSnapshot(listOf(saved("a", 1))), SyncSnapshot(listOf(saved("b", 2))))
        assertEquals(listOf("example.com/b", "example.com/a"), merged.items.map { it.id })
    }

    @Test fun removalBeatsOlderCopiesButNotNewerOnes() {
        val removedAt3 = SyncSnapshot(deleted = mapOf("example.com/a" to at(3)))
        assertTrue(CollectionSync.merge(SyncSnapshot(listOf(saved("a", 0, 2))), removedAt3).items.isEmpty())
        // Edited (or saved again) after the removal on another device: it stays.
        val kept = CollectionSync.merge(SyncSnapshot(listOf(saved("a", 0, 4))), removedAt3)
        assertEquals(1, kept.items.size)
        assertTrue(kept.deleted.isEmpty())
    }

    @Test fun removalsPropagate() {
        val merged = CollectionSync.merge(SyncSnapshot(deleted = mapOf("x" to at(1))), SyncSnapshot(deleted = mapOf("x" to at(2))))
        assertEquals(mapOf("x" to at(2)), merged.deleted)
    }

    @Test fun mergeIsSymmetricAndIdempotent() {
        val a = SyncSnapshot(listOf(saved("a", 0, 1), saved("b", 1, 6)), mapOf("example.com/c" to at(4)))
        val b = SyncSnapshot(listOf(saved("b", 1, 3), saved("c", 2, 2), saved("d", 3)))
        val ab = CollectionSync.merge(a, b)
        assertEquals(ab, CollectionSync.merge(b, a))
        assertEquals(ab, CollectionSync.merge(ab, ab))
        assertEquals(listOf("example.com/d", "example.com/b", "example.com/a"), ab.items.map { it.id })
    }
}

class StoreSyncTest {
    private val dir = createTempDirectory().toFile()
    @AfterTest fun cleanup() { dir.deleteRecursively() }

    @Test fun editsAreStampedAndRemovalsRecorded() {
        val store = BriefStore(dir)
        store.updateCollection(at(0)) { it.add(saved("a", 0)); it.add(saved("b", 0)) }
        store.updateCollection(at(5)) { items -> items[0] = items[0].copy(note = "n") }
        val items = store.loadCollection()
        assertEquals(at(5), items[0].updatedAt)
        assertEquals(at(0), items[1].updatedAt)

        store.updateCollection(at(9)) { items -> items.removeAll { it.id == "example.com/b" } }
        assertEquals(mapOf("example.com/b" to at(9)), store.loadDeleted())
        // Saving it again clears the removal.
        store.updateCollection(at(10)) { it.add(saved("b", 10)) }
        assertTrue(store.loadDeleted().isEmpty())
    }

    @Test fun oldFilesWithoutUpdatedAtStillLoad() {
        dir.resolve("collection.json").writeText(
            """[{"item":{"id":"x","title":"T","summary":"","url":"https://x","kind":"blog","source":"B","metric":"","rawScore":1,"field":"Agents"},
               "savedAt":"2026-10-21T18:02:11Z","tags":[],"note":"","isRead":false}]""",
        )
        val item = BriefStore(dir).loadCollection().single()
        assertEquals(null, item.updatedAt)
        assertEquals(Instant.parse("2026-10-21T18:02:11Z"), item.changedAt)
    }
}

/** Two devices syncing through one shared remote copy. */
class SyncerTest {
    private class FakeRemote : RemoteCollection {
        var file: SyncSnapshot? = null
        var writes = 0
        override suspend fun find() = if (file != null) "id" else null
        override suspend fun read(id: String) = file!!
        override suspend fun create(snapshot: SyncSnapshot): String { file = snapshot; writes++; return "id" }
        override suspend fun update(id: String, snapshot: SyncSnapshot) { file = snapshot; writes++ }
    }

    private val dirs = List(2) { createTempDirectory().toFile() }
    @AfterTest fun cleanup() { dirs.forEach { it.deleteRecursively() } }

    @Test fun twoDevicesConverge() = runBlocking {
        val remote = FakeRemote()
        val (phone, mac) = dirs.map(::BriefStore)
        phone.updateCollection(at(1)) { it.add(saved("a", 1)) }
        mac.updateCollection(at(2)) { it.add(saved("b", 2)) }

        CollectionSyncer(phone, remote).sync()
        val macSync = CollectionSyncer(mac, remote).sync()
        assertTrue(macSync.changedLocally)
        CollectionSyncer(phone, remote).sync()
        assertEquals(phone.loadCollection(), mac.loadCollection())
        assertEquals(2, phone.loadCollection().size)

        // Removing on the Mac removes it on the phone.
        mac.updateCollection(at(3)) { items -> items.removeAll { it.id == "example.com/a" } }
        CollectionSyncer(mac, remote).sync()
        CollectionSyncer(phone, remote).sync()
        assertEquals(listOf("example.com/b"), phone.loadCollection().map { it.id })

        // Nothing changed: no upload.
        val writes = remote.writes
        assertFalse(CollectionSyncer(phone, remote).sync().uploaded)
        assertEquals(writes, remote.writes)
    }
}
