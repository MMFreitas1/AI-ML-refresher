package com.mmfreitas.aibrief.core

import java.time.Instant
import kotlin.math.ln
import kotlin.math.max

data class RankingConfig(
    val maxItems: Int = 15,
    /** At most this many items from one source kind, so one busy source can't take over. */
    val perKindCap: Int = 3,
    /** At most this many items from one field, so LLM news doesn't crowd out everything else. */
    val perFieldCap: Int = 4,
    /** Trust in each source's popularity signal. A source's #1 item scores exactly its weight. */
    val weights: Map<SourceKind, Double> = mapOf(
        SourceKind.githubTrending to 1.0,
        SourceKind.hfPapers to 1.0,
        SourceKind.hackerNews to 0.95,
        SourceKind.githubNew to 0.9,
        SourceKind.hfModels to 0.9,
        SourceKind.reddit to 0.85,
        SourceKind.blog to 0.8,
        SourceKind.hfSpaces to 0.7,
    ),
)

/**
 * Deterministic ranking: same inputs always give the same list. Same formula as the macOS app.
 *
 * 1. Drop items already shown on previous days.
 * 2. De-duplicate by canonical URL, keeping the copy from the higher-weight source.
 * 3. Within each source, score = weight × log(1 + raw) / log(1 + best raw in that source).
 *    Log scaling keeps a 10k-star outlier from flattening everything else.
 * 4. Sort by score (ties: raw score, then newest, then title) and pick greedily under the caps.
 */
object Ranker {
    fun rank(items: Iterable<BriefItem>, seen: Set<String> = emptySet(), config: RankingConfig = RankingConfig()): List<BriefItem> {
        fun weight(k: SourceKind) = config.weights[k] ?: 0.5

        val byID = LinkedHashMap<String, BriefItem>()
        for (item in items) {
            if (item.id in seen) continue
            val existing = byID[item.id]
            if (existing != null && weight(existing.kind) >= weight(item.kind)) continue
            byID[item.id] = item
        }

        val scored = byID.values.groupBy { it.kind }.flatMap { (kind, group) ->
            val best = group.maxOf { it.rawScore }
            group.map { item ->
                val relative = if (best > 0) ln(1 + max(item.rawScore, 0.0)) / ln(1 + best) else 1.0
                item.copy(score = weight(kind) * relative)
            }
        }.sortedWith(
            compareByDescending<BriefItem> { it.score }
                .thenByDescending { it.rawScore }
                .thenByDescending { it.publishedAt ?: Instant.MIN }
                .thenBy { it.title }
        )

        val picked = mutableListOf<BriefItem>()
        val kindCount = mutableMapOf<SourceKind, Int>()
        val fieldCount = mutableMapOf<Field, Int>()
        for (item in scored) {
            if (picked.size >= config.maxItems) break
            if ((kindCount[item.kind] ?: 0) >= config.perKindCap || (fieldCount[item.field] ?: 0) >= config.perFieldCap) continue
            picked += item
            kindCount.merge(item.kind, 1, Int::plus)
            fieldCount.merge(item.field, 1, Int::plus)
        }
        return picked
    }
}
