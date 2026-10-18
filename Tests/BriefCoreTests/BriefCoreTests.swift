@testable import BriefCore
import Foundation
import Testing

private func item(_ title: String, _ kind: SourceKind, _ raw: Double, url: String? = nil, field: Field = .llm) -> BriefItem {
    BriefItem(url: URL(string: url ?? "https://example.com/\(kind.rawValue)/\(title)")!, title: title,
              summary: "", kind: kind, source: kind.label, metric: "", rawScore: raw, field: field)
}

@Suite struct CategorizerTests {
    @Test func fields() {
        #expect(Categorizer.field(for: "Whole-brain connectome of the fruit fly") == .neuro)
        #expect(Categorizer.field(for: "A VLA policy for humanoid manipulation") == .robotics)
        #expect(Categorizer.field(for: "Streaming TTS with 80ms latency") == .audio)
        #expect(Categorizer.field(for: "FP4 inference kernels for Blackwell") == .systems)
        #expect(Categorizer.field(for: "Scaling LLMs to longer context") == .llm)
        #expect(Categorizer.field(for: "A new kind of spreadsheet") == .general)
    }

    @Test func wordBoundaries() {
        // "rl" must not match inside "world", "ai" not inside "said".
        #expect(Categorizer.field(for: "Hello world") == .general)
        #expect(!Categorizer.isAIRelated("She said hello"))
        #expect(Categorizer.isAIRelated("Meta reduces employee use of Claude AI"))
        #expect(Categorizer.isAIRelated("Show HN: a local LLMs benchmark"))
        #expect(!Categorizer.isAIRelated("Margaret Hamilton has died"))
    }
}

@Suite struct RankerTests {
    @Test func normalizesWithinSourceAndAppliesWeights() {
        let ranked = Ranker.rank([
            item("hn-top", .hackerNews, 900), item("hn-low", .hackerNews, 30),
            item("paper-top", .hfPapers, 160), item("paper-low", .hfPapers, 2),
        ])
        #expect(ranked.map(\.title) == ["paper-top", "hn-top", "hn-low", "paper-low"])
        #expect(ranked[0].score == 1.0)
        #expect(ranked[1].score == 0.95)
    }

    @Test func capsPerSourceAndField() {
        var config = RankingConfig()
        config.perKindCap = 2
        config.perFieldCap = 3
        let items = (1...5).map { item("gh\($0)", .githubTrending, Double(100 * $0), field: .agents) }
            + (1...5).map { item("p\($0)", .hfPapers, Double($0), field: .agents) }
            + [item("robot", .hfModels, 5, field: .robotics)]
        let ranked = Ranker.rank(items, config: config)
        #expect(ranked.filter { $0.kind == .githubTrending }.count == 2)
        #expect(ranked.filter { $0.field == .agents }.count == 3)
        #expect(ranked.contains { $0.title == "robot" })
    }

    @Test func dedupesAndExcludesSeen() {
        let a = item("repo", .githubTrending, 10, url: "https://github.com/a/b")
        let b = item("repo", .githubNew, 10, url: "https://www.github.com/a/b/")
        let c = item("old", .githubTrending, 50, url: "https://github.com/old/repo")
        let ranked = Ranker.rank([a, b, c], excluding: ["github.com/old/repo"])
        #expect(ranked.count == 1)
        #expect(ranked[0].kind == .githubTrending)
    }

    @Test func deterministic() {
        let items = (1...30).map { item("i\($0)", SourceKind.allCases[$0 % 8], Double($0 % 7)) }
        #expect(Ranker.rank(items).map(\.id) == Ranker.rank(items.reversed()).map(\.id))
    }
}

@Suite struct ParserTests {
    @Test func githubTrendingRow() {
        let html = """
        <article class="Box-row"><h2><a href="/org/llm-tool">org / llm-tool</a></h2>
        <p class="col-9 color-fg-muted my-1 tmp-pr-4">
          Fast LLM inference &amp; serving
        </p>
        <a href="/org/llm-tool/stargazers">12,710</a>
        <span class="d-inline-block float-sm-right">4,640 stars today</span></article>
        """
        let items = GitHubTrendingSource.parse(html)
        #expect(items.count == 1)
        #expect(items[0].title == "org/llm-tool")
        #expect(items[0].summary == "Fast LLM inference & serving")
        #expect(items[0].rawScore == 4640)
    }

    @Test func rssAndAtom() throws {
        let rss = """
        <rss><channel><item><title><![CDATA[Hello <b>RSS</b>]]></title><link>https://a.com/1</link>
        <description>Body</description><pubDate>Thu, 08 Oct 2026 11:26:09 GMT</pubDate></item></channel></rss>
        """
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Hi Atom</title>
        <link rel="alternate" href="https://b.com/2"/><published>2026-10-08T10:00:00Z</published>
        <summary>Sum</summary></entry></feed>
        """
        let r = try FeedParser.parse(Data(rss.utf8))
        let a = try FeedParser.parse(Data(atom.utf8))
        #expect(r.first?.title == "Hello RSS")
        #expect(r.first?.link == "https://a.com/1")
        #expect(r.first?.date != nil)
        #expect(a.first?.link == "https://b.com/2")
        #expect(a.first?.date != nil)
    }
}

@Suite struct ScheduleAndStoreTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Lisbon")!; return c }()

    func date(_ h: Int, day: Int = 8) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h))!
    }

    @Test func dueOnlyAfterNoonOncePerDay() {
        #expect(!Schedule.isDue(now: date(11), latestDay: "2026-10-07", calendar: cal))
        #expect(Schedule.isDue(now: date(13), latestDay: "2026-10-07", calendar: cal))
        #expect(!Schedule.isDue(now: date(13), latestDay: "2026-10-08", calendar: cal))
        #expect(Schedule.nextRefresh(after: date(13), calendar: cal) == date(12, day: 9))
    }

    @Test func collectionRoundTripAndSeen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BriefStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = item("a", .blog, 1)
        try store.save(DailyBrief(day: "2026-10-07", generatedAt: .now, items: [a], errors: []))
        #expect(store.seenIDs(before: "2026-10-08") == [a.id])
        #expect(store.seenIDs(before: "2026-10-07").isEmpty)

        #expect(try store.save(item: a))
        #expect(try !store.save(item: a))
        try store.updateCollection { $0[0].tags = ["rl"]; $0[0].isRead = true }
        let saved = BriefStore(directory: dir).loadCollection()
        #expect(saved.count == 1 && saved[0].tags == ["rl"] && saved[0].isRead)
    }
}
