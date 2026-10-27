package com.mmfreitas.aibrief.core

import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

private fun item(title: String, kind: SourceKind, raw: Double, url: String? = null, field: Field = Field.Llm) =
    BriefItem.make(url ?: "https://example.com/$kind/$title", title, "", kind, kind.label, "", raw, field = field)

class CategorizerTest {
    @Test fun fields() {
        assertEquals(Field.Neuro, Categorizer.fieldFor("Whole-brain connectome of the fruit fly"))
        assertEquals(Field.Robotics, Categorizer.fieldFor("A VLA policy for humanoid manipulation"))
        assertEquals(Field.Audio, Categorizer.fieldFor("Streaming TTS with 80ms latency"))
        assertEquals(Field.Systems, Categorizer.fieldFor("FP4 inference kernels for Blackwell"))
        assertEquals(Field.Llm, Categorizer.fieldFor("Scaling LLMs to longer context"))
        assertEquals(Field.General, Categorizer.fieldFor("A new kind of spreadsheet"))
    }

    @Test fun wordBoundaries() {
        // "rl" must not match inside "world", "ai" not inside "said".
        assertEquals(Field.General, Categorizer.fieldFor("Hello world"))
        assertFalse(Categorizer.isAIRelated("She said hello"))
        assertTrue(Categorizer.isAIRelated("Meta reduces employee use of Claude AI"))
        assertTrue(Categorizer.isAIRelated("Show HN: a local LLMs benchmark"))
        assertFalse(Categorizer.isAIRelated("Margaret Hamilton has died"))
    }
}

class RankerTest {
    @Test fun normalizesWithinSourceAndAppliesWeights() {
        val ranked = Ranker.rank(listOf(
            item("hn-top", SourceKind.hackerNews, 900.0), item("hn-low", SourceKind.hackerNews, 30.0),
            item("paper-top", SourceKind.hfPapers, 160.0), item("paper-low", SourceKind.hfPapers, 2.0),
        ))
        assertEquals(listOf("paper-top", "hn-top", "hn-low", "paper-low"), ranked.map { it.title })
        assertEquals(1.0, ranked[0].score)
        assertEquals(0.95, ranked[1].score)
    }

    @Test fun capsPerSourceAndField() {
        val config = RankingConfig(perKindCap = 2, perFieldCap = 3)
        val items = (1..5).map { item("gh$it", SourceKind.githubTrending, 100.0 * it, field = Field.Agents) } +
            (1..5).map { item("p$it", SourceKind.hfPapers, it.toDouble(), field = Field.Agents) } +
            item("robot", SourceKind.hfModels, 5.0, field = Field.Robotics)
        val ranked = Ranker.rank(items, config = config)
        assertEquals(2, ranked.count { it.kind == SourceKind.githubTrending })
        assertEquals(3, ranked.count { it.field == Field.Agents })
        assertTrue(ranked.any { it.title == "robot" })
    }

    @Test fun dedupesAndExcludesSeen() {
        val a = item("repo", SourceKind.githubTrending, 10.0, url = "https://github.com/a/b")
        val b = item("repo", SourceKind.githubNew, 10.0, url = "https://www.github.com/a/b/")
        val c = item("old", SourceKind.githubTrending, 50.0, url = "https://github.com/old/repo")
        val ranked = Ranker.rank(listOf(a, b, c), setOf("github.com/old/repo"))
        assertEquals(1, ranked.size)
        assertEquals(SourceKind.githubTrending, ranked[0].kind)
    }

    @Test fun deterministic() {
        val kinds = SourceKind.entries
        val items = (1..30).map { item("i$it", kinds[it % 8], (it % 7).toDouble()) }
        assertEquals(Ranker.rank(items).map { it.id }, Ranker.rank(items.reversed()).map { it.id })
    }
}

class ParserTest {
    @Test fun githubTrendingRow() {
        val html = """
            <article class="Box-row"><h2><a href="/org/llm-tool">org / llm-tool</a></h2>
            <p class="col-9 color-fg-muted my-1 tmp-pr-4">
              Fast LLM inference &amp; serving
            </p>
            <a href="/org/llm-tool/stargazers">12,710</a>
            <span class="d-inline-block float-sm-right">4,640 stars today</span></article>
        """.trimIndent()
        val items = GitHubTrendingSource.parse(html)
        assertEquals(1, items.size)
        assertEquals("org/llm-tool", items[0].title)
        assertEquals("Fast LLM inference & serving", items[0].summary)
        assertEquals(4640.0, items[0].rawScore)
    }

    @Test fun rssAndAtom() {
        val rss = """
            <rss><channel><item><title><![CDATA[Hello <b>RSS</b>]]></title><link>https://a.com/1</link>
            <description>Body&nbsp;text</description><pubDate>Thu, 08 Oct 2026 11:26:09 GMT</pubDate></item></channel></rss>
        """.trimIndent()
        val atom = """
            <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Hi Atom</title>
            <link rel="alternate" href="https://b.com/2"/><published>2026-10-08T10:00:00Z</published>
            <summary>Sum</summary></entry></feed>
        """.trimIndent()
        val r = FeedParser.parse(rss.toByteArray())
        val a = FeedParser.parse(atom.toByteArray())
        assertEquals("Hello RSS", r[0].title)
        assertEquals("https://a.com/1", r[0].link)
        assertEquals(Instant.parse("2026-10-08T11:26:09Z"), r[0].date)
        assertEquals("https://b.com/2", a[0].link)
        assertNotNull(a[0].date)
    }

    @Test fun rfc822Dates() {
        for (s in listOf("Thu, 08 Oct 2026 11:26:09 +0000", "Thu, 8 Oct 2026 07:26:09 -0400", "Thu, 08 Oct 2026 04:26:09 PDT"))
            assertEquals(Instant.parse("2026-10-08T11:26:09Z"), FeedParser.parseDate(s), s)
    }

    @Test fun canonicalIds() {
        assertEquals("github.com/a/b", Canonical.id("https://www.GitHub.com/a/b/?tab=readme#x"))
        assertEquals("arxiv.org/abs/2610.1", Canonical.id("https://arxiv.org/pdf/2610.1"))
    }
}

class ScheduleAndStoreTest {
    private val lisbon = ZoneId.of("Europe/Lisbon")
    private fun date(h: Int, day: Int = 8) = LocalDateTime.of(2026, 10, day, h, 0).atZone(lisbon).toInstant()

    @Test fun dueOnlyAfterNoonOncePerDay() {
        assertFalse(Schedule.isDue(date(11), "2026-10-07", lisbon))
        assertTrue(Schedule.isDue(date(13), "2026-10-07", lisbon))
        assertFalse(Schedule.isDue(date(13), "2026-10-08", lisbon))
        assertEquals(date(12, day = 9), Schedule.nextRefresh(date(13), lisbon))
        assertEquals(date(12), Schedule.nextRefresh(date(9), lisbon))
    }

    @Test fun collectionRoundTripAndSeen() {
        val dir = createTempDirectory().toFile()
        try {
            val store = BriefStore(dir)
            val a = item("a", SourceKind.blog, 1.0)
            store.save(DailyBrief("2026-10-07", Instant.now(), listOf(a)))
            assertEquals(setOf(a.id), store.seenIDs(before = "2026-10-08"))
            assertTrue(store.seenIDs(before = "2026-10-07").isEmpty())

            assertTrue(store.save(a))
            assertFalse(store.save(a))
            store.updateCollection { it[0] = it[0].copy(tags = listOf("rl"), isRead = true) }
            val saved = BriefStore(dir).loadCollection()
            assertTrue(saved.size == 1 && saved[0].tags == listOf("rl") && saved[0].isRead)
        } finally {
            dir.deleteRecursively()
        }
    }

    /** The files are interchangeable with the macOS and Windows apps'. */
    @Test fun readsMacOSFormat() {
        val json = """
            [{"isRead":false,"item":{"discussionURL":"https://arxiv.org/abs/2610.1","field":"Video & 3D","id":"huggingface.co/papers/2610.1",
              "kind":"hfPapers","metric":"9 upvotes","rawScore":9,"score":1,"source":"HF Papers","summary":"S","title":"T",
              "url":"https://huggingface.co/papers/2610.1"},"note":"n","savedAt":"2026-10-21T18:02:11Z","tags":["x"]}]
        """.trimIndent()
        val serializer = kotlinx.serialization.builtins.ListSerializer(SavedItem.serializer())
        val items = BriefStore.json.decodeFromString(serializer, json)
        assertEquals(Field.Video, items[0].item.field)
        assertEquals(SourceKind.hfPapers, items[0].item.kind)
        val back = BriefStore.json.encodeToString(serializer, items)
        assertTrue("\"savedAt\": \"2026-10-21T18:02:11Z\"" in back, back)
        assertTrue("\"field\": \"Video & 3D\"" in back, back)
        assertFalse("publishedAt" in back, back)
    }
}
