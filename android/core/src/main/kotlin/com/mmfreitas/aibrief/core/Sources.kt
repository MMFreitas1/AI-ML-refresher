package com.mmfreitas.aibrief.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import java.net.URI
import java.net.URLEncoder
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import kotlin.math.ceil
import kotlin.math.max

interface BriefSource {
    val name: String
    suspend fun fetch(http: Http, now: Instant): List<BriefItem>
}

private fun encode(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

// MARK: - GitHub

/** github.com/trending (no official API). Ranked by "stars today", AI repos only. */
class GitHubTrendingSource(
    /** The overall page plus Python, where most ML repos live. */
    private val pages: List<String> = listOf("https://github.com/trending?since=daily", "https://github.com/trending/python?since=daily"),
) : BriefSource {
    override val name = "GitHub Trending"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> {
        val items = pages.flatMap { parse(http.text(it)) }
        if (items.isEmpty()) throw FetchError.parse("GitHub trending page (layout may have changed)")
        return items.filter { Categorizer.isAIRelated("${it.title} ${it.summary}") }
    }

    companion object {
        private val stargazers = Regex("href=\"/([^/\"]+/[^/\"]+)/stargazers\"")
        private val description = Regex("<p class=\"col-9[^\"]*\">([\\s\\S]*?)</p>")
        private val starsToday = Regex("""([\d,]+) stars? today""")

        fun parse(html: String): List<BriefItem> = html.split("<article class=\"Box-row\">").drop(1).mapNotNull { row ->
            val repo = stargazers.find(row)?.groupValues?.get(1) ?: return@mapNotNull null
            val summary = description.find(row)?.let { Format.stripHTML(it.groupValues[1]) } ?: ""
            val today = starsToday.find(row)?.groupValues?.get(1)?.replace(",", "")?.toDoubleOrNull() ?: 0.0
            BriefItem.make("https://github.com/$repo", repo, summary, SourceKind.githubTrending, "GitHub Trending",
                "${Format.compact(today)}★ today", today)
        }
    }
}

/** Repos created in the last two weeks under ML topics, ranked by stars per day of age. */
class GitHubNewReposSource(
    private val topics: List<String> = listOf("llm", "machine-learning", "deep-learning", "computer-vision",
        "reinforcement-learning", "robotics", "ai-agents"),
    private val windowDays: Long = 14,
) : BriefSource {
    override val name = "New on GitHub"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> {
        val since = Day.string(now.minus(Duration.ofDays(windowDays)))
        val headers = buildMap {
            put("Accept", "application/vnd.github+json")
            http.githubToken?.takeIf { it.isNotEmpty() }?.let { put("Authorization", "Bearer $it") }
        }
        val repos = LinkedHashMap<String, kotlinx.serialization.json.JsonElement>()
        for (topic in topics) {
            val q = encode("topic:$topic created:>=$since")
            val json = http.json("https://api.github.com/search/repositories?q=$q&sort=stars&order=desc&per_page=10", headers)
            for (repo in json.obj("items")?.array ?: emptyList()) repo.str("full_name")?.let { repos[it] = repo }
        }
        return repos.values.map { r ->
            val name = r.str("full_name")!!
            val description = r.str("description") ?: ""
            val stars = r.num("stargazers_count") ?: 0.0
            val created = Iso8601.parse(r.str("created_at")) ?: now
            val days = max(Duration.between(created, now).toMillis() / 86_400_000.0, 1.0)
            val topics = r.strings("topics").joinToString(" ")
            BriefItem.make(r.str("html_url") ?: "https://github.com/$name", name, description,
                SourceKind.githubNew, "New on GitHub", "${Format.compact(stars)}★ in ${ceil(days).toInt()}d",
                stars / days, field = Categorizer.fieldFor("$name $description $topics"), publishedAt = created)
        }
    }
}

// MARK: - Hugging Face

/** Community-upvoted papers (successor of Papers with Code). Uses the latest complete day. */
class HFPapersSource : BriefSource {
    override val name = "HF Papers"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> {
        // Yesterday's list has had a full day of votes. Weekends can be sparse, so step back if needed.
        for (daysBack in 1L..4L) {
            val day = Day.string(now.minus(Duration.ofDays(daysBack)), ZoneOffset.UTC)
            val entries = http.json("https://huggingface.co/api/daily_papers?date=$day&limit=100").array
            if (entries.size < 5) continue
            return entries.mapNotNull { it.obj("paper") }.map { p ->
                val id = p.str("id") ?: ""
                val votes = p.num("upvotes") ?: 0.0
                BriefItem.make("https://huggingface.co/papers/$id", p.str("title") ?: id,
                    Format.truncate(p.str("summary") ?: ""), SourceKind.hfPapers, "HF Papers",
                    "${votes.toInt()} upvotes", votes, discussionURL = "https://arxiv.org/abs/$id",
                    publishedAt = Iso8601.parse(p.str("publishedAt")))
            }
        }
        return emptyList()
    }
}

class HFModelsSource : BriefSource {
    override val name = "HF Models"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> =
        http.json("https://huggingface.co/api/models?sort=trendingScore&limit=25").array.map { m ->
            val id = m.str("id") ?: ""
            val task = m.str("pipeline_tag") ?: "model"
            val likes = m.num("likes")
            val summary = listOfNotNull(task, m.str("library_name"), likes?.let { "${Format.compact(it)} likes" }).joinToString(" · ")
            val trending = m.num("trendingScore") ?: 0.0
            BriefItem.make("https://huggingface.co/$id", id, summary, SourceKind.hfModels, "HF Models",
                "trending ${trending.toInt()}", trending,
                field = HFTask.fieldFor(task) ?: Categorizer.fieldFor("$id ${m.strings("tags").joinToString(" ")}"),
                publishedAt = Iso8601.parse(m.str("createdAt")))
        }
}

class HFSpacesSource : BriefSource {
    override val name = "HF Spaces"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> =
        http.json("https://huggingface.co/api/spaces?sort=trendingScore&limit=25&expand[]=cardData&expand[]=likes&expand[]=trendingScore&expand[]=createdAt")
            .array.map { s ->
                val id = s.str("id") ?: ""
                val card = s.obj("cardData")
                val title = card?.str("title")?.let { "$it ($id)" } ?: id
                val trending = s.num("trendingScore") ?: 0.0
                BriefItem.make("https://huggingface.co/spaces/$id", title, card?.str("short_description") ?: "Hugging Face Space",
                    SourceKind.hfSpaces, "HF Spaces", "trending ${trending.toInt()}", trending,
                    publishedAt = Iso8601.parse(s.str("createdAt")))
            }
}

internal object HFTask {
    fun fieldFor(t: String): Field? {
        if ("video" in t || "3d" in t) return Field.Video
        if ("audio" in t || "speech" in t || "voice" in t) return Field.Audio
        if ("image" in t || "object-detection" in t || "depth" in t || "segmentation" in t || "visual" in t) return Field.Vision
        return when (t) {
            "robotics" -> Field.Robotics
            "reinforcement-learning" -> Field.Rl
            "text-generation", "text2text-generation", "feature-extraction", "sentence-similarity",
            "text-classification", "translation", "summarization", "fill-mask", "token-classification" -> Field.Llm
            else -> null
        }
    }
}

// MARK: - Community

/** Hacker News stories from the last 24h that mention AI/ML, ranked by points. */
class HackerNewsSource(private val minPoints: Int = 30) : BriefSource {
    override val name = "Hacker News"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> {
        val since = now.epochSecond - 86_400
        val filters = encode("created_at_i>$since,points>$minPoints")
        val json = http.json("https://hn.algolia.com/api/v1/search?tags=story&numericFilters=$filters&hitsPerPage=200")
        return (json.obj("hits")?.array ?: emptyList()).mapNotNull { h ->
            val title = h.str("title")
            if (title == null || !Categorizer.isAIRelated(title)) return@mapNotNull null
            val discussion = "https://news.ycombinator.com/item?id=${h.str("objectID")}"
            val url = h.str("url")?.takeIf(::isAbsoluteURL) ?: discussion
            val points = h.num("points") ?: 0.0
            BriefItem.make(url, title, "via ${URI(url).host}", SourceKind.hackerNews, "Hacker News",
                "${points.toInt()} pts · ${(h.num("num_comments") ?: 0.0).toInt()} comments", points,
                discussionURL = discussion,
                publishedAt = Instant.ofEpochSecond((h.num("created_at_i") ?: 0.0).toLong()))
        }
    }
}

/** Reddit's daily top posts via RSS. The feed carries no scores, so rank order is the signal.
 *  Reddit rate-limits anonymous clients hard, hence few subreddits and a pause between them. */
class RedditSource(
    private val subreddits: List<String> = listOf("MachineLearning", "LocalLLaMA"),
    private val perSub: Int = 10,
) : BriefSource {
    override val name = "Reddit"
    private val submittedBy = Regex("submitted by.*$", RegexOption.DOT_MATCHES_ALL)

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> {
        val items = mutableListOf<BriefItem>()
        var lastError: Exception? = null
        subreddits.forEachIndexed { i, sub ->
            if (i > 0) delay(3_000)
            val entries = try {
                FeedParser.parse(http.data("https://www.reddit.com/r/$sub/top/.rss?t=day&limit=$perSub")).take(perSub)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                lastError = e
                return@forEachIndexed
            }
            entries.forEachIndexed { rank, e ->
                if (!isAbsoluteURL(e.link)) return@forEachIndexed
                items += BriefItem.make(e.link, e.title, Format.truncate(submittedBy.replace(e.summary, "")),
                    SourceKind.reddit, "r/$sub", "#${rank + 1} today on r/$sub",
                    (perSub - rank).toDouble(), publishedAt = e.date)
            }
        }
        if (items.isEmpty()) lastError?.let { throw it }
        return items
    }
}

// MARK: - Blogs & newsletters

/** Curated writing. Feeds carry no popularity signal, so every new post scores equally and the
 *  newest win ties. Only posts from the last [windowHours] count as new. */
class BlogSource(
    private val feeds: List<Feed> = defaultFeeds,
    private val windowHours: Long = 48,
) : BriefSource {
    /**
     * @param aiOnly For general-purpose feeds, keep only AI-related posts.
     * @param fieldHint Field to use when the keyword rules find nothing specific.
     */
    data class Feed(val name: String, val url: String, val aiOnly: Boolean = false, val fieldHint: Field? = null)

    override val name = "Blogs"

    override suspend fun fetch(http: Http, now: Instant): List<BriefItem> = coroutineScope {
        val cutoff = now.minus(Duration.ofHours(windowHours))
        val results = feeds.map { feed ->
            async {
                try {
                    FeedParser.parse(http.data(feed.url)).mapNotNull { e ->
                        val date = e.date ?: return@mapNotNull null
                        if (date < cutoff || date > now.plus(Duration.ofHours(1)) || !isAbsoluteURL(e.link)) return@mapNotNull null
                        if (feed.aiOnly && !Categorizer.isAIRelated("${e.title} ${e.summary}")) return@mapNotNull null
                        var field = Categorizer.fieldFor("${e.title} ${e.summary}")
                        if (field == Field.General && feed.fieldHint != null) field = feed.fieldHint
                        BriefItem.make(e.link, e.title, Format.truncate(e.summary), SourceKind.blog, feed.name,
                            feed.name, 1.0, field = field, publishedAt = date)
                    } to null
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    emptyList<BriefItem>() to "${feed.name}: ${e.message}"
                }
            }
        }.awaitAll()
        val items = results.flatMap { it.first }
        val failures = results.mapNotNull { it.second }
        // A single dead feed shouldn't sink the others; only fail when everything failed.
        if (items.isEmpty() && failures.size == feeds.size) throw FetchError.parse("all blog feeds (${failures.firstOrNull()})")
        items
    }

    companion object {
        val defaultFeeds = listOf(
            Feed("Import AI", "https://importai.substack.com/feed"),
            Feed("Latent Space", "https://www.latent.space/feed"),
            Feed("Interconnects", "https://www.interconnects.ai/feed"),
            Feed("Ahead of AI", "https://magazine.sebastianraschka.com/feed"),
            Feed("Last Week in AI", "https://lastweekin.ai/feed"),
            Feed("Simon Willison", "https://simonwillison.net/atom/entries/", aiOnly = true),
            Feed("Google DeepMind", "https://deepmind.google/blog/rss.xml"),
            Feed("OpenAI", "https://openai.com/news/rss.xml"),
            Feed("Hugging Face Blog", "https://huggingface.co/blog/feed.xml"),
            Feed("BAIR", "https://bair.berkeley.edu/blog/feed.xml"),
            Feed("NVIDIA", "https://blogs.nvidia.com/feed/", aiOnly = true),
            Feed("The Robot Report", "https://www.therobotreport.com/feed/", fieldHint = Field.Robotics),
            Feed("The Transmitter", "https://www.thetransmitter.org/feed/", fieldHint = Field.Neuro),
        )
    }
}
