package com.mmfreitas.aibrief.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URI
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import java.util.Locale
import java.util.zip.GZIPInputStream

open class Http(
    val userAgent: String = "AI-ML-Refresher/1.0 (+https://github.com/MMFreitas1/AI-ML-refresher)",
    /** Optional, raises GitHub's search rate limit. */
    val githubToken: String? = System.getenv("GITHUB_TOKEN"),
) {
    open suspend fun data(url: String, headers: Map<String, String> = emptyMap()): ByteArray = withContext(Dispatchers.IO) {
        val conn = URI(url).toURL().openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = 30_000
            conn.readTimeout = 30_000
            conn.setRequestProperty("User-Agent", userAgent)
            conn.setRequestProperty("Accept-Encoding", "gzip")
            headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
            val code = conn.responseCode
            if (code !in 200..299) throw FetchError.status(code, URI(url).host)
            val stream = if (conn.contentEncoding.equals("gzip", ignoreCase = true)) GZIPInputStream(conn.inputStream) else conn.inputStream
            stream.use { it.readBytes() }
        } catch (e: SocketTimeoutException) {
            throw FetchError("timed out")
        } finally {
            conn.disconnect()
        }
    }

    suspend fun text(url: String): String = data(url).toString(Charsets.UTF_8)

    suspend fun json(url: String, headers: Map<String, String> = emptyMap()): JsonElement {
        val bytes = data(url, headers)
        return try {
            lenient.parseToJsonElement(bytes.toString(Charsets.UTF_8))
        } catch (e: Exception) {
            throw FetchError.parse("JSON from ${URI(url).host}")
        }
    }

    private companion object {
        val lenient = Json { ignoreUnknownKeys = true }
    }
}

class FetchError(message: String) : IOException(message) {
    companion object {
        fun status(code: Int, host: String) =
            FetchError(if (code == 429) "$host rate-limited the request (HTTP 429)" else "$host returned HTTP $code")

        fun parse(what: String) = FetchError("Could not parse $what")
    }
}

object Iso8601 {
    fun parse(s: String?): Instant? {
        if (s.isNullOrBlank()) return null
        return try {
            OffsetDateTime.parse(s).toInstant()
        } catch (_: DateTimeParseException) {
            // No offset: treat as UTC, as the other apps do.
            runCatching { Instant.parse(s + "Z") }.getOrNull()
                ?: runCatching { java.time.LocalDate.parse(s).atStartOfDay().toInstant(java.time.ZoneOffset.UTC) }.getOrNull()
        }
    }
}

object Format {
    /** 12345 → "12.3k" */
    fun compact(n: Double): String = when {
        n >= 1_000_000 -> String.format(Locale.ROOT, "%.1fM", n / 1_000_000)
        n >= 10_000 -> String.format(Locale.ROOT, "%.0fk", n / 1_000)
        n >= 1_000 -> String.format(Locale.ROOT, "%.1fk", n / 1_000)
        else -> n.toInt().toString()
    }

    private val tags = Regex("<[^>]+>")
    private val spaces = Regex("\\s+")
    private val entities = listOf(
        "&amp;" to "&", "&lt;" to "<", "&gt;" to ">", "&quot;" to "\"",
        "&#39;" to "'", "&#x27;" to "'", "&nbsp;" to " ", "&#32;" to " ",
    )

    fun stripHTML(html: String): String {
        var s = tags.replace(html, " ")
        for ((entity, ch) in entities) s = s.replace(entity, ch)
        return spaces.replace(s, " ").trim()
    }

    fun truncate(s: String, n: Int = 240): String = if (s.length <= n) s else s.substring(0, n).trim() + "…"
}

/** Null-tolerant readers for the loosely typed JSON the sources return. */
internal fun JsonElement.str(name: String): String? =
    ((this as? JsonObject)?.get(name) as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonElement.num(name: String): Double? =
    ((this as? JsonObject)?.get(name) as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull

internal fun JsonElement.obj(name: String): JsonElement? =
    (this as? JsonObject)?.get(name)?.takeIf { it !is JsonNull }

internal fun JsonElement.strings(name: String): List<String> =
    (obj(name) as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: emptyList()

internal val JsonElement.array: List<JsonElement> get() = (this as? JsonArray) ?: emptyList()

internal fun isAbsoluteURL(s: String): Boolean =
    runCatching { URI(s) }.getOrNull()?.let { it.isAbsolute && it.host != null } ?: false
