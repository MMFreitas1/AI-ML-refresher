package com.mmfreitas.aibrief.core

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.temporal.ChronoUnit

/** Seconds precision, like the stored dates, so a value compares equal after a round trip. */
object Clock {
    fun now(): Instant = Instant.now().truncatedTo(ChronoUnit.SECONDS)
}

/** A collection plus its removals: what is synced. */
@Serializable
data class SyncSnapshot(
    val items: List<SavedItem> = emptyList(),
    val deleted: Map<String, @Serializable(with = SwiftDateSerializer::class) Instant> = emptyMap(),
)

/**
 * Merging two copies of the collection (this device's and the synced file). Same rules in the
 * macOS and Windows apps, so any device can merge with any other:
 *
 * - Per item, the copy changed last (updatedAt, else savedAt) wins. Ties keep the first argument's.
 * - A removal wins over copies changed at or before it; an item saved again later comes back.
 * - Removal times are kept (the latest per item) so a removal reaches devices that sync later.
 * - The result is ordered newest saved first, like the collection itself.
 */
object CollectionSync {
    fun merge(local: SyncSnapshot, remote: SyncSnapshot): SyncSnapshot {
        val deleted = HashMap(local.deleted)
        remote.deleted.forEach { (id, at) -> deleted.merge(id, at) { a, b -> maxOf(a, b) } }

        val byID = LinkedHashMap<String, SavedItem>()
        for (item in local.items + remote.items) {
            val existing = byID[item.id]
            if (existing == null || item.changedAt > existing.changedAt) byID[item.id] = item
        }
        val items = byID.values
            .filter { item -> deleted[item.id]?.let { item.changedAt > it } ?: true }
            .sortedWith(compareByDescending<SavedItem> { it.savedAt }.thenBy { it.id })
        // An item that outlived its removal no longer needs the removal record.
        items.forEach { deleted.remove(it.id) }
        return SyncSnapshot(items, deleted.toSortedMap())
    }
}
