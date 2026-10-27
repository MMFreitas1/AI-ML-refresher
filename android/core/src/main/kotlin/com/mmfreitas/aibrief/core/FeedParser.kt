package com.mmfreitas.aibrief.core

import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserException
import org.xmlpull.v1.XmlPullParserFactory
import java.io.ByteArrayInputStream
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Minimal RSS 2.0 / Atom parser: title, link, summary and date per entry. */
data class FeedEntry(val title: String, val link: String, val summary: String, val date: Instant?)

object FeedParser {
    fun parse(data: ByteArray): List<FeedEntry> {
        val entries = mutableListOf<FeedEntry>()
        var title: String? = null
        var link: String? = null
        var summary: String? = null
        var dateText: String? = null
        var inEntry = false
        val text = StringBuilder()

        fun end(name: String) {
            if (!inEntry) { text.clear(); return }
            val value = text.toString().trim()
            when (name) {
                "title" -> title = Format.stripHTML(value)
                "link" -> if (value.isNotEmpty()) link = value
                "description", "summary" -> summary = Format.stripHTML(value)
                "content", "content:encoded" -> if (summary.isNullOrEmpty()) summary = Format.stripHTML(value)
                "pubDate", "published", "updated", "dc:date" -> if (dateText.isNullOrEmpty() || name == "published") dateText = value
                "item", "entry" -> {
                    link?.takeIf { it.isNotEmpty() }?.let { entries += FeedEntry(title ?: "", it, summary ?: "", parseDate(dateText)) }
                    inEntry = false
                }
            }
            text.clear()
        }

        try {
            val parser = XmlPullParserFactory.newInstance().newPullParser()
            // Feeds often use HTML entities (&nbsp;) that strict XML rejects.
            runCatching { parser.setFeature("http://xmlpull.org/v1/doc/features.html#relaxed", true) }
            parser.setInput(ByteArrayInputStream(data), null)
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                when (event) {
                    XmlPullParser.START_TAG -> {
                        text.clear()
                        val name = parser.name
                        if (name == "item" || name == "entry") {
                            inEntry = true
                            title = null; link = null; summary = null; dateText = null
                        } else if (name == "link" && inEntry) {
                            // Atom: <link rel="alternate" href="…"/>. Prefer the alternate link over others.
                            val href = parser.getAttributeValue(null, "href")
                            if (href != null && (parser.getAttributeValue(null, "rel") ?: "alternate") == "alternate") link = href
                        }
                    }
                    XmlPullParser.TEXT -> text.append(parser.text)
                    XmlPullParser.END_TAG -> end(parser.name)
                }
                event = parser.next()
            }
        } catch (e: XmlPullParserException) {
            if (entries.isEmpty()) throw FetchError.parse("feed: ${e.message}")
        }
        return entries
    }

    private val rfc822Zone = Regex("""^(.*\d)\s+([A-Z]{1,3}|[+-]\d{4})$""")
    private val formats = listOf("EEE, d MMM yyyy HH:mm:ss xxx", "EEE, d MMM yyyy HH:mm xxx", "d MMM yyyy HH:mm:ss xxx")
        .map { DateTimeFormatter.ofPattern(it, Locale.ENGLISH) }

    /** ISO 8601 (Atom) or RFC 822 (RSS), e.g. "Thu, 08 Oct 2026 11:26:09 GMT" or "… +0000". */
    fun parseDate(raw: String?): Instant? {
        if (raw.isNullOrBlank()) return null
        val s = raw.trim()
        if (s[0].isDigit()) return Iso8601.parse(s)
        // Normalize the zone to an offset java.time understands.
        val m = rfc822Zone.find(s) ?: return null
        val zone = m.groupValues[2]
        val offset = when (zone) {
            "GMT", "UT", "UTC", "Z" -> "+00:00"
            "EST" -> "-05:00"; "EDT" -> "-04:00"; "CST" -> "-06:00"; "CDT" -> "-05:00"
            "MST" -> "-07:00"; "MDT" -> "-06:00"; "PST" -> "-08:00"; "PDT" -> "-07:00"
            else -> if (zone.length == 5) "${zone.substring(0, 3)}:${zone.substring(3)}" else return null
        }
        val text = "${m.groupValues[1].replace(Regex("\\s+"), " ")} $offset"
        for (f in formats) runCatching { return OffsetDateTime.parse(text, f).toInstant() }
        return null
    }
}
