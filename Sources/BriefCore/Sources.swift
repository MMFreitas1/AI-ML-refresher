import Foundation

public protocol BriefSource: Sendable {
    var name: String { get }
    func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem]
}

// MARK: - GitHub

/// github.com/trending (no official API). Ranked by "stars today", AI repos only.
public struct GitHubTrendingSource: BriefSource {
    public let name = "GitHub Trending"
    /// The overall page plus Python, where most ML repos live.
    var pages = ["https://github.com/trending?since=daily", "https://github.com/trending/python?since=daily"]

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        var items: [BriefItem] = []
        for page in pages {
            let html = String(decoding: try await http.data(URL(string: page)!), as: UTF8.self)
            items += Self.parse(html)
        }
        if items.isEmpty { throw FetchError.parse("GitHub trending page (layout may have changed)") }
        return items.filter { Categorizer.isAIRelated("\($0.title) \($0.summary)") }
    }

    static func parse(_ html: String) -> [BriefItem] {
        html.components(separatedBy: "<article class=\"Box-row\">").dropFirst().compactMap { row in
            guard let repo = row.firstMatch(#"href="/([^/"]+/[^/"]+)/stargazers""#),
                  let url = URL(string: "https://github.com/\(repo)") else { return nil }
            let description = row.firstMatch(#"<p class="col-9[^"]*">([\s\S]*?)</p>"#).map(Format.stripHTML) ?? ""
            let today = Double(row.firstMatch(#"([\d,]+) stars? today"#)?.replacingOccurrences(of: ",", with: "") ?? "") ?? 0
            return BriefItem(url: url, title: repo, summary: description, kind: .githubTrending,
                             source: "GitHub Trending", metric: "\(Format.compact(today))★ today", rawScore: today)
        }
    }
}

/// Repos created in the last two weeks under ML topics, ranked by stars per day of age.
public struct GitHubNewReposSource: BriefSource {
    public let name = "New on GitHub"
    var topics = ["llm", "machine-learning", "deep-learning", "computer-vision",
                  "reinforcement-learning", "robotics", "ai-agents"]
    var windowDays = 14

    struct Response: Decodable { let items: [Repo] }
    struct Repo: Decodable {
        let full_name: String
        let html_url: URL
        let description: String?
        let stargazers_count: Double
        let created_at: Date
        let topics: [String]?
    }

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        let since = Day.string(for: now.addingTimeInterval(-Double(windowDays) * 86_400))
        var headers = ["Accept": "application/vnd.github+json"]
        if let token = http.githubToken { headers["Authorization"] = "Bearer \(token)" }

        var repos: [String: Repo] = [:]
        for topic in topics {
            var c = URLComponents(string: "https://api.github.com/search/repositories")!
            c.queryItems = [.init(name: "q", value: "topic:\(topic) created:>=\(since)"),
                            .init(name: "sort", value: "stars"), .init(name: "order", value: "desc"),
                            .init(name: "per_page", value: "10")]
            for repo in try await http.json(Response.self, from: c.url!, headers: headers).items {
                repos[repo.full_name] = repo
            }
        }
        return repos.values.map { r in
            let days = max(now.timeIntervalSince(r.created_at) / 86_400, 1)
            let topics = (r.topics ?? []).joined(separator: " ")
            return BriefItem(url: r.html_url, title: r.full_name, summary: r.description ?? "",
                             kind: .githubNew, source: "New on GitHub",
                             metric: "\(Format.compact(r.stargazers_count))★ in \(Int(days.rounded(.up)))d",
                             rawScore: r.stargazers_count / days,
                             field: Categorizer.field(for: "\(r.full_name) \(r.description ?? "") \(topics)"),
                             publishedAt: r.created_at)
        }
    }
}

// MARK: - Hugging Face

/// Community-upvoted papers (successor of Papers with Code). Uses the latest complete day.
public struct HFPapersSource: BriefSource {
    public let name = "HF Papers"

    struct Entry: Decodable { let paper: Paper }
    struct Paper: Decodable {
        let id: String
        let title: String
        let summary: String?
        let upvotes: Double?
        let publishedAt: Date?
        let githubRepo: String?
    }

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // Yesterday's list has had a full day of votes. Weekends can be sparse, so step back if needed.
        for daysBack in 1...4 {
            let day = Day.string(for: now.addingTimeInterval(-Double(daysBack) * 86_400), calendar: utc)
            let url = URL(string: "https://huggingface.co/api/daily_papers?date=\(day)&limit=100")!
            let entries = try await http.json([Entry].self, from: url)
            if entries.count >= 5 {
                return entries.map { e in
                    let p = e.paper
                    let votes = p.upvotes ?? 0
                    return BriefItem(url: URL(string: "https://huggingface.co/papers/\(p.id)")!,
                                     title: p.title, summary: Format.truncate(p.summary ?? ""),
                                     kind: .hfPapers, source: "HF Papers", metric: "\(Int(votes)) upvotes",
                                     rawScore: votes, discussionURL: URL(string: "https://arxiv.org/abs/\(p.id)"),
                                     publishedAt: p.publishedAt)
                }
            }
        }
        return []
    }
}

public struct HFModelsSource: BriefSource {
    public let name = "HF Models"

    struct Model: Decodable {
        let id: String
        let likes: Double?
        let trendingScore: Double?
        let pipeline_tag: String?
        let library_name: String?
        let tags: [String]?
        let createdAt: Date?
    }

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        let url = URL(string: "https://huggingface.co/api/models?sort=trendingScore&limit=25")!
        return try await http.json([Model].self, from: url).map { m in
            let task = m.pipeline_tag ?? "model"
            let summary = [task, m.library_name, m.likes.map { "\(Format.compact($0)) likes" }]
                .compactMap { $0 }.joined(separator: " · ")
            return BriefItem(url: URL(string: "https://huggingface.co/\(m.id)")!, title: m.id, summary: summary,
                             kind: .hfModels, source: "HF Models",
                             metric: "trending \(Int(m.trendingScore ?? 0))", rawScore: m.trendingScore ?? 0,
                             field: HFTask.field(task) ?? Categorizer.field(for: "\(m.id) \((m.tags ?? []).joined(separator: " "))"),
                             publishedAt: m.createdAt)
        }
    }
}

public struct HFSpacesSource: BriefSource {
    public let name = "HF Spaces"

    struct Space: Decodable {
        let id: String
        let likes: Double?
        let trendingScore: Double?
        let cardData: Card?
        let createdAt: Date?
    }
    struct Card: Decodable {
        let title: String?
        let short_description: String?
    }

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        let url = URL(string: "https://huggingface.co/api/spaces?sort=trendingScore&limit=25&expand[]=cardData&expand[]=likes&expand[]=trendingScore&expand[]=createdAt")!
        return try await http.json([Space].self, from: url).map { s in
            let title = s.cardData?.title.map { "\($0) (\(s.id))" } ?? s.id
            return BriefItem(url: URL(string: "https://huggingface.co/spaces/\(s.id)")!, title: title,
                             summary: s.cardData?.short_description ?? "Hugging Face Space",
                             kind: .hfSpaces, source: "HF Spaces",
                             metric: "trending \(Int(s.trendingScore ?? 0))", rawScore: s.trendingScore ?? 0,
                             publishedAt: s.createdAt)
        }
    }
}

enum HFTask {
    static func field(_ task: String) -> Field? {
        switch task {
        case let t where t.contains("video") || t.contains("3d"): .video
        case let t where t.contains("audio") || t.contains("speech") || t.contains("voice"): .audio
        case let t where t.contains("image") || t.contains("object-detection") || t.contains("depth")
            || t.contains("segmentation") || t.contains("visual"): .vision
        case "robotics": .robotics
        case "reinforcement-learning": .rl
        case "text-generation", "text2text-generation", "feature-extraction", "sentence-similarity",
             "text-classification", "translation", "summarization", "fill-mask", "token-classification": .llm
        default: nil
        }
    }
}

// MARK: - Community

/// Hacker News stories from the last 24h that mention AI/ML, ranked by points.
public struct HackerNewsSource: BriefSource {
    public let name = "Hacker News"
    var minPoints = 30

    struct Response: Decodable { let hits: [Hit] }
    struct Hit: Decodable {
        let objectID: String
        let title: String?
        let url: String?
        let points: Double?
        let num_comments: Double?
        let created_at_i: Double
    }

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        let since = Int(now.timeIntervalSince1970) - 86_400
        var c = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        c.queryItems = [.init(name: "tags", value: "story"),
                        .init(name: "numericFilters", value: "created_at_i>\(since),points>\(minPoints)"),
                        .init(name: "hitsPerPage", value: "200")]
        return try await http.json(Response.self, from: c.url!).hits.compactMap { h in
            guard let title = h.title, Categorizer.isAIRelated(title) else { return nil }
            let discussion = URL(string: "https://news.ycombinator.com/item?id=\(h.objectID)")!
            let url = h.url.flatMap(URL.init(string:)) ?? discussion
            let points = h.points ?? 0
            return BriefItem(url: url, title: title, summary: url.host.map { "via \($0)" } ?? "Ask/Show HN",
                             kind: .hackerNews, source: "Hacker News",
                             metric: "\(Int(points)) pts · \(Int(h.num_comments ?? 0)) comments",
                             rawScore: points, discussionURL: discussion,
                             publishedAt: Date(timeIntervalSince1970: h.created_at_i))
        }
    }
}

/// Reddit's daily top posts via RSS. The feed carries no scores, so rank order is the signal.
/// Reddit rate-limits anonymous clients hard, hence few subreddits and a pause between them.
public struct RedditSource: BriefSource {
    public let name = "Reddit"
    var subreddits = ["MachineLearning", "LocalLLaMA"]
    var perSub = 10

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        var items: [BriefItem] = []
        var lastError: Error?
        for (i, sub) in subreddits.enumerated() {
            if i > 0 { try await Task.sleep(for: .seconds(3)) }
            let url = URL(string: "https://www.reddit.com/r/\(sub)/top/.rss?t=day&limit=\(perSub)")!
            let entries: ArraySlice<FeedEntry>
            do { entries = try FeedParser.parse(try await http.data(url)).prefix(perSub) }
            catch { lastError = error; continue }
            for (rank, e) in entries.enumerated() {
                guard let link = URL(string: e.link) else { continue }
                items.append(BriefItem(url: link, title: e.title,
                                       summary: Format.truncate(e.summary.replacingOccurrences(of: "submitted by.*$", with: "", options: .regularExpression)),
                                       kind: .reddit, source: "r/\(sub)", metric: "#\(rank + 1) today on r/\(sub)",
                                       rawScore: Double(perSub - rank), publishedAt: e.date))
            }
        }
        if items.isEmpty, let lastError { throw lastError }
        return items
    }
}

// MARK: - Blogs & newsletters

/// Curated writing. Feeds carry no popularity signal, so every new post scores equally
/// and the newest win ties. Only posts from the last `windowHours` count as new.
public struct BlogSource: BriefSource {
    public struct Feed: Sendable {
        public var name: String
        public var url: String
        /// For general-purpose feeds, keep only AI-related posts.
        public var aiOnly = false
        /// Field to use when the keyword rules find nothing specific.
        public var fieldHint: Field? = nil
    }

    public let name = "Blogs"
    var windowHours = 48.0

    public static let defaultFeeds: [Feed] = [
        Feed(name: "Import AI", url: "https://importai.substack.com/feed"),
        Feed(name: "Latent Space", url: "https://www.latent.space/feed"),
        Feed(name: "Interconnects", url: "https://www.interconnects.ai/feed"),
        Feed(name: "Ahead of AI", url: "https://magazine.sebastianraschka.com/feed"),
        Feed(name: "Last Week in AI", url: "https://lastweekin.ai/feed"),
        Feed(name: "Simon Willison", url: "https://simonwillison.net/atom/entries/", aiOnly: true),
        Feed(name: "Google DeepMind", url: "https://deepmind.google/blog/rss.xml"),
        Feed(name: "OpenAI", url: "https://openai.com/news/rss.xml"),
        Feed(name: "Hugging Face Blog", url: "https://huggingface.co/blog/feed.xml"),
        Feed(name: "BAIR", url: "https://bair.berkeley.edu/blog/feed.xml"),
        Feed(name: "NVIDIA", url: "https://blogs.nvidia.com/feed/", aiOnly: true),
        Feed(name: "The Robot Report", url: "https://www.therobotreport.com/feed/", fieldHint: .robotics),
        Feed(name: "The Transmitter", url: "https://www.thetransmitter.org/feed/", fieldHint: .neuro),
    ]

    var feeds: [Feed] = BlogSource.defaultFeeds

    public func fetch(_ http: HTTP, now: Date) async throws -> [BriefItem] {
        let cutoff = now.addingTimeInterval(-windowHours * 3600)
        var failures: [String] = []
        let items = await withTaskGroup(of: Result<[BriefItem], Error>.self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        let entries = try FeedParser.parse(try await http.data(URL(string: feed.url)!))
                        return .success(entries.compactMap { e in
                            guard let date = e.date, date >= cutoff, date <= now.addingTimeInterval(3600),
                                  let url = URL(string: e.link) else { return nil }
                            if feed.aiOnly && !Categorizer.isAIRelated("\(e.title) \(e.summary)") { return nil }
                            var field = Categorizer.field(for: "\(e.title) \(e.summary)")
                            if field == .general, let hint = feed.fieldHint { field = hint }
                            return BriefItem(url: url, title: e.title, summary: Format.truncate(e.summary),
                                             kind: .blog, source: feed.name, metric: feed.name,
                                             rawScore: 1, field: field, publishedAt: date)
                        })
                    } catch {
                        return .failure(NSError(domain: feed.name, code: 0,
                                                userInfo: [NSLocalizedDescriptionKey: "\(feed.name): \(error.localizedDescription)"]))
                    }
                }
            }
            var all: [BriefItem] = []
            for await result in group {
                switch result {
                case let .success(items): all += items
                case let .failure(error): failures.append(error.localizedDescription)
                }
            }
            return all
        }
        // A single dead feed shouldn't sink the others; only fail when everything failed.
        if items.isEmpty && failures.count == feeds.count {
            throw FetchError.parse("all blog feeds (\(failures.first ?? ""))")
        }
        return items
    }
}

// MARK: - Helpers

extension String {
    /// First capture group of `pattern`, or nil.
    func firstMatch(_ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: self) else { return nil }
        return String(self[r])
    }
}
