package com.mmfreitas.aibrief.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant

/**
 * Plain JSON files on disk, in the same format as the macOS and Windows apps (so the files can move between them):
 *
 *     <dir>/briefs/2026-10-08.json   one ranked list per day (kept as history)
 *     <dir>/collection.json          saved items with tags, notes and read state
 *     <dir>/deleted.json             when each removed item was removed, so removals sync
 *
 * On Android, <dir> is the app's private files folder.
 */
class BriefStore(val directory: File) {
    private val briefsDirectory = File(directory, "briefs").apply { mkdirs() }
    private val collectionFile = File(directory, "collection.json")
    private val deletedFile = File(directory, "deleted.json")
    private val lock = Any()

    // MARK: Briefs

    fun save(brief: DailyBrief) =
        writeAtomic(File(briefsDirectory, "${brief.day}.json"), json.encodeToString(DailyBrief.serializer(), brief))

    fun brief(day: String): DailyBrief? =
        runCatching { json.decodeFromString(DailyBrief.serializer(), File(briefsDirectory, "$day.json").readText()) }.getOrNull()

    /** Days with a saved brief, newest first. */
    fun availableDays(): List<String> =
        (briefsDirectory.listFiles { f -> f.extension == "json" } ?: emptyArray())
            .map { it.nameWithoutExtension }.sortedDescending()

    fun latestBrief(): DailyBrief? = availableDays().firstNotNullOfOrNull(::brief)

    /** Item IDs shown in the [days] briefs before [before], so the same repo isn't served again tomorrow. */
    fun seenIDs(before: String, days: Int = 7): Set<String> =
        availableDays().filter { it < before }.take(days).mapNotNull(::brief).flatMap { b -> b.items.map { it.id } }.toSet()

    // MARK: Collection

    fun loadCollection(): List<SavedItem> = synchronized(lock) { readCollection() }

    /**
     * Read-modify-write under a lock, so the widget and the app don't overwrite each other.
     * Changed items get a new updatedAt and removed ones a deletion time, for syncing.
     */
    fun updateCollection(now: Instant = Clock.now(), mutate: (MutableList<SavedItem>) -> Unit): List<SavedItem> = synchronized(lock) {
        val before = readCollection().associateBy { it.id }
        val items = readCollection().toMutableList()
        mutate(items)
        for (i in items.indices) {
            val old = before[items[i].id]
            if (old != items[i]) items[i] = items[i].copy(updatedAt = now)
        }
        val deleted = readDeleted().toMutableMap()
        val kept = items.mapTo(HashSet()) { it.id }
        val removed = before.keys - kept
        if (removed.isNotEmpty() || kept.any { it in deleted }) {
            removed.forEach { deleted[it] = now }
            kept.forEach { deleted.remove(it) }
            writeAtomic(deletedFile, json.encodeToString(deletedSerializer, deleted))
        }
        writeAtomic(collectionFile, json.encodeToString(collectionSerializer, items))
        items
    }

    /** Removed item IDs and when they were removed. */
    fun loadDeleted(): Map<String, Instant> = synchronized(lock) { readDeleted() }

    /**
     * Applies a sync: merges [remote] into the collection under the lock, without re-stamping, and
     * returns the merged state. Anything changed locally meanwhile is part of the merge, not lost.
     */
    fun mergeCollection(remote: SyncSnapshot): SyncSnapshot = synchronized(lock) {
        val merged = CollectionSync.merge(SyncSnapshot(readCollection(), readDeleted()), remote)
        writeAtomic(deletedFile, json.encodeToString(deletedSerializer, merged.deleted))
        writeAtomic(collectionFile, json.encodeToString(collectionSerializer, merged.items))
        merged
    }

    /** Adds the item if it isn't saved yet. Returns false when it was already there. */
    fun save(item: BriefItem): Boolean {
        var added = false
        updateCollection { items ->
            if (items.none { it.id == item.id }) {
                items.add(0, SavedItem(item))
                added = true
            }
        }
        return added
    }

    private fun readCollection(): List<SavedItem> =
        runCatching { json.decodeFromString(collectionSerializer, collectionFile.readText()) }.getOrDefault(emptyList())

    private fun readDeleted(): Map<String, Instant> =
        runCatching { json.decodeFromString(deletedSerializer, deletedFile.readText()) }.getOrDefault(emptyMap())

    private fun writeAtomic(file: File, text: String) {
        val tmp = File(file.path + ".tmp")
        tmp.writeText(text)
        Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    companion object {
        private val collectionSerializer = ListSerializer(SavedItem.serializer())
        internal val deletedSerializer = MapSerializer(String.serializer(), SwiftDateSerializer)

        @OptIn(ExperimentalSerializationApi::class)
        val json = Json {
            prettyPrint = true
            prettyPrintIndent = "  "
            ignoreUnknownKeys = true
            explicitNulls = false
            encodeDefaults = true
        }
    }
}
