package com.mmfreitas.aibrief.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import java.net.SocketTimeoutException
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

class BriefBuilder(
    private val sources: List<BriefSource> = defaultSources(),
    private val config: RankingConfig = RankingConfig(),
    private val http: Http = Http(),
) {
    /** Fetches every source in parallel, ranks, and saves today's brief.
     *  Failing sources are recorded in errors instead of failing the whole run. */
    suspend fun run(store: BriefStore, now: Instant = Instant.now().truncatedTo(ChronoUnit.SECONDS)): DailyBrief {
        val (candidates, errors) = fetchAll(now)
        val day = Day.string(now)
        val items = Ranker.rank(candidates, store.seenIDs(before = day), config)
        val brief = DailyBrief(day, now, items, errors)
        // Don't replace a good brief with an empty one when offline.
        if (items.isEmpty()) store.brief(day)?.takeIf { it.items.isNotEmpty() }?.let { return it }
        store.save(brief)
        return brief
    }

    suspend fun fetchAll(now: Instant): Pair<List<BriefItem>, List<String>> = coroutineScope {
        val results = sources.map { source ->
            async {
                try {
                    source.fetch(http, now) to null
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val message = if (e is SocketTimeoutException) "timed out" else e.message ?: e.javaClass.simpleName
                    emptyList<BriefItem>() to "${source.name}: $message"
                }
            }
        }.awaitAll()
        results.flatMap { it.first } to results.mapNotNull { it.second }.sorted()
    }

    companion object {
        fun defaultSources(): List<BriefSource> = listOf(
            GitHubTrendingSource(), GitHubNewReposSource(), HFPapersSource(), HFModelsSource(),
            HFSpacesSource(), HackerNewsSource(), RedditSource(), BlogSource(),
        )
    }
}

/** When a new brief is due: once per day, at or after 12:00 local time. */
object Schedule {
    const val REFRESH_HOUR = 12

    fun todaysRefresh(now: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant =
        now.atZone(zone).toLocalDate().atTime(REFRESH_HOUR, 0).atZone(zone).toInstant()

    fun nextRefresh(now: Instant, zone: ZoneId = ZoneId.systemDefault()): Instant {
        val today = todaysRefresh(now, zone)
        return if (now < today) today
        else ZonedDateTime.ofInstant(today, zone).plusDays(1).withHour(REFRESH_HOUR).withMinute(0).toInstant()
    }

    /** True after noon when today's brief hasn't been built yet (also covers a phone off at noon). */
    fun isDue(now: Instant, latestDay: String?, zone: ZoneId = ZoneId.systemDefault()): Boolean =
        now >= todaysRefresh(now, zone) && latestDay != Day.string(now, zone)
}
