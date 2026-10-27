package com.mmfreitas.aibrief.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** Broad research area an item belongs to. Assigned by deterministic keyword rules (see [Categorizer]). */
@Serializable(with = FieldSerializer::class)
enum class Field(val label: String) {
    Llm("LLMs & NLP"),
    Agents("Agents"),
    Vision("Vision"),
    Video("Video & 3D"),
    Audio("Audio & Speech"),
    Robotics("Robotics"),
    Rl("Reinforcement Learning"),
    Neuro("Neuroscience"),
    Systems("Systems & Infra"),
    General("General AI");

    companion object {
        fun fromLabel(label: String): Field? = entries.firstOrNull { it.label == label }
    }
}

/** Where an item came from. Each kind is ranked within itself before items are merged.
 *  Stored by name ("githubTrending"), matching the macOS and Windows apps. */
@Suppress("EnumEntryName")
@Serializable
enum class SourceKind(val label: String) {
    githubTrending("GitHub Trending"),
    githubNew("New on GitHub"),
    hfPapers("HF Papers"),
    hfModels("HF Models"),
    hfSpaces("HF Spaces"),
    hackerNews("Hacker News"),
    reddit("Reddit"),
    blog("Blogs"),
}

@Serializable
data class BriefItem(
    /** Canonical URL, used for de-duplication across sources and days. */
    val id: String,
    val title: String,
    val summary: String,
    val url: String,
    val discussionURL: String? = null,
    val kind: SourceKind,
    /** Specific origin, e.g. "r/LocalLLaMA" or "Import AI". */
    val source: String,
    /** Human readable popularity signal, e.g. "4,640★ today". */
    val metric: String,
    /** Popularity signal used for ranking inside its source (stars, upvotes, points…). */
    val rawScore: Double,
    /** Normalized cross-source score in 0...1, set by [Ranker]. */
    val score: Double = 0.0,
    val field: Field = Field.General,
    @Serializable(with = SwiftDateSerializer::class)
    val publishedAt: Instant? = null,
) {
    companion object {
        fun make(
            url: String, title: String, summary: String, kind: SourceKind, source: String,
            metric: String, rawScore: Double, discussionURL: String? = null,
            field: Field? = null, publishedAt: Instant? = null,
        ) = BriefItem(
            id = Canonical.id(url),
            title = title.trim(),
            summary = summary.trim(),
            url = url,
            discussionURL = discussionURL,
            kind = kind,
            source = source,
            metric = metric,
            rawScore = rawScore,
            field = field ?: Categorizer.fieldFor("$title $summary"),
            publishedAt = publishedAt,
        )
    }
}

/**
 * @param day Local calendar day, yyyy-MM-dd.
 * @param errors Sources that failed during this run, shown in the UI so silent gaps are visible.
 */
@Serializable
data class DailyBrief(
    val day: String,
    @Serializable(with = SwiftDateSerializer::class) val generatedAt: Instant,
    val items: List<BriefItem>,
    val errors: List<String> = emptyList(),
)

@Serializable
data class SavedItem(
    val item: BriefItem,
    @Serializable(with = SwiftDateSerializer::class) val savedAt: Instant = Instant.now().truncatedTo(ChronoUnit.SECONDS),
    val tags: List<String> = emptyList(),
    val note: String = "",
    val isRead: Boolean = false,
    /** Last change to tags, note or read state, for syncing. Absent in files from before sync: then savedAt. */
    @Serializable(with = SwiftDateSerializer::class) val updatedAt: Instant? = null,
) {
    val id: String get() = item.id
    val changedAt: Instant get() = updatedAt ?: savedAt
}

object Canonical {
    /** Lowercased host+path without scheme, www., query, fragment or trailing slash. */
    fun id(url: String): String {
        val uri = runCatching { URI(url) }.getOrNull()
        val rawHost = uri?.host
        if (uri == null || rawHost == null || !uri.isAbsolute) return url.lowercase()
        var host = rawHost.lowercase()
        if (host.startsWith("www.")) host = host.substring(4)
        var path = runCatching { URLDecoder.decode((uri.rawPath ?: "").replace("+", "%2B"), "UTF-8") }
            .getOrDefault(uri.path ?: "").trimEnd('/')
        // arXiv abs/pdf links point at the same paper.
        if (host == "arxiv.org") path = path.replace("/pdf/", "/abs/")
        return host + path.lowercase()
    }
}

object Day {
    private val format = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    /** yyyy-MM-dd in the given time zone (the user's local one by default). */
    fun string(date: Instant, zone: ZoneId = ZoneId.systemDefault()): String = format.format(date.atZone(zone))
}

/** ISO 8601 without fractional seconds, in UTC: what Swift's .iso8601 strategy reads and writes. */
object SwiftDateSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("SwiftDate", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeString(DateTimeFormatter.ISO_INSTANT.format(value.truncatedTo(ChronoUnit.SECONDS)))
    override fun deserialize(decoder: Decoder): Instant =
        Iso8601.parse(decoder.decodeString()) ?: throw IllegalArgumentException("Bad date")
}

/** Fields are stored by their display name, as in the macOS app. */
object FieldSerializer : KSerializer<Field> {
    override val descriptor = PrimitiveSerialDescriptor("Field", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Field) = encoder.encodeString(value.label)
    override fun deserialize(decoder: Decoder): Field = Field.fromLabel(decoder.decodeString()) ?: Field.General
}
