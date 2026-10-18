import Foundation

/// Broad research area an item belongs to. Assigned by deterministic keyword rules (see `Categorizer`).
public enum Field: String, Codable, CaseIterable, Sendable {
    case llm = "LLMs & NLP"
    case agents = "Agents"
    case vision = "Vision"
    case video = "Video & 3D"
    case audio = "Audio & Speech"
    case robotics = "Robotics"
    case rl = "Reinforcement Learning"
    case neuro = "Neuroscience"
    case systems = "Systems & Infra"
    case general = "General AI"

    public var symbol: String {
        switch self {
        case .llm: "text.bubble"
        case .agents: "person.2.wave.2"
        case .vision: "eye"
        case .video: "film"
        case .audio: "waveform"
        case .robotics: "gearshape.2"
        case .rl: "arrow.triangle.2.circlepath"
        case .neuro: "brain"
        case .systems: "cpu"
        case .general: "sparkles"
        }
    }
}

/// Where an item came from. Each kind is ranked within itself before items are merged.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case githubTrending
    case githubNew
    case hfPapers
    case hfModels
    case hfSpaces
    case hackerNews
    case reddit
    case blog

    public var label: String {
        switch self {
        case .githubTrending: "GitHub Trending"
        case .githubNew: "New on GitHub"
        case .hfPapers: "HF Papers"
        case .hfModels: "HF Models"
        case .hfSpaces: "HF Spaces"
        case .hackerNews: "Hacker News"
        case .reddit: "Reddit"
        case .blog: "Blogs"
        }
    }
}

public struct BriefItem: Codable, Identifiable, Hashable, Sendable {
    /// Canonical URL, used for de-duplication across sources and days.
    public var id: String
    public var title: String
    public var summary: String
    public var url: URL
    public var discussionURL: URL?
    public var kind: SourceKind
    /// Specific origin, e.g. "r/LocalLLaMA" or "Import AI".
    public var source: String
    /// Human readable popularity signal, e.g. "4,640★ today".
    public var metric: String
    /// Popularity signal used for ranking inside its source (stars, upvotes, points…).
    public var rawScore: Double
    /// Normalized cross-source score in 0...1, set by `Ranker`.
    public var score: Double
    public var field: Field
    public var publishedAt: Date?

    public init(url: URL, title: String, summary: String, kind: SourceKind, source: String,
                metric: String, rawScore: Double, discussionURL: URL? = nil,
                field: Field? = nil, publishedAt: Date? = nil) {
        self.id = Canonical.id(for: url)
        self.title = title.trimmed
        self.summary = summary.trimmed
        self.url = url
        self.discussionURL = discussionURL
        self.kind = kind
        self.source = source
        self.metric = metric
        self.rawScore = rawScore
        self.score = 0
        self.field = field ?? Categorizer.field(for: "\(title) \(summary)")
        self.publishedAt = publishedAt
    }
}

public struct DailyBrief: Codable, Sendable {
    /// Local calendar day, `yyyy-MM-dd`.
    public var day: String
    public var generatedAt: Date
    public var items: [BriefItem]
    /// Sources that failed during this run, shown in the UI so silent gaps are visible.
    public var errors: [String]

    public init(day: String, generatedAt: Date, items: [BriefItem], errors: [String]) {
        self.day = day
        self.generatedAt = generatedAt
        self.items = items
        self.errors = errors
    }
}

public struct SavedItem: Codable, Identifiable, Hashable, Sendable {
    public var item: BriefItem
    public var savedAt: Date
    public var tags: [String]
    public var note: String
    public var isRead: Bool

    public var id: String { item.id }

    public init(item: BriefItem, savedAt: Date = .now, tags: [String] = [], note: String = "", isRead: Bool = false) {
        self.item = item
        self.savedAt = savedAt
        self.tags = tags
        self.note = note
        self.isRead = isRead
    }
}

enum Canonical {
    /// Lowercased host+path without scheme, `www.`, query, fragment or trailing slash.
    static func id(for url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        // arXiv abs/pdf links point at the same paper.
        if host == "arxiv.org" { path = path.replacingOccurrences(of: "/pdf/", with: "/abs/") }
        return host + path.lowercased()
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

public enum Day {
    /// `yyyy-MM-dd` in the user's current time zone.
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
