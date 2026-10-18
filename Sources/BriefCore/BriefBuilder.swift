import Foundation

public struct BriefBuilder: Sendable {
    public static let defaultSources: [any BriefSource] = [
        GitHubTrendingSource(), GitHubNewReposSource(), HFPapersSource(), HFModelsSource(),
        HFSpacesSource(), HackerNewsSource(), RedditSource(), BlogSource(),
    ]

    public var sources: [any BriefSource]
    public var config: RankingConfig
    public var http: HTTP

    public init(sources: [any BriefSource] = BriefBuilder.defaultSources,
                config: RankingConfig = RankingConfig(), http: HTTP = HTTP()) {
        self.sources = sources
        self.config = config
        self.http = http
    }

    /// Fetches every source in parallel, ranks, and saves today's brief.
    /// Failing sources are recorded in `errors` instead of failing the whole run.
    @discardableResult
    public func run(store: BriefStore, now: Date = .now) async throws -> DailyBrief {
        let (candidates, errors) = await fetchAll(now: now)
        let day = Day.string(for: now)
        let items = Ranker.rank(candidates, excluding: store.seenIDs(before: day), config: config)
        let brief = DailyBrief(day: day, generatedAt: now, items: items, errors: errors)
        // Don't replace a good brief with an empty one when offline.
        if items.isEmpty, let existing = store.brief(for: day), !existing.items.isEmpty {
            return existing
        }
        try store.save(brief)
        return brief
    }

    public func fetchAll(now: Date = .now) async -> (items: [BriefItem], errors: [String]) {
        await withTaskGroup(of: (String, Result<[BriefItem], Error>).self) { group in
            for source in sources {
                group.addTask {
                    do { return (source.name, .success(try await source.fetch(http, now: now))) }
                    catch { return (source.name, .failure(error)) }
                }
            }
            var items: [BriefItem] = []
            var errors: [String] = []
            for await (name, result) in group {
                switch result {
                case let .success(fetched): items += fetched
                case let .failure(error): errors.append("\(name): \(error.localizedDescription)")
                }
            }
            return (items, errors.sorted())
        }
    }
}

/// When a new brief is due: once per day, at or after 12:00 local time.
public enum Schedule {
    public static let refreshHour = 12

    public static func todaysRefresh(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: refreshHour, minute: 0, second: 0, of: now)!
    }

    public static func nextRefresh(after now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = todaysRefresh(now, calendar: calendar)
        return now < today ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// True after noon when today's brief hasn't been built yet (also covers a Mac asleep at noon).
    public static func isDue(now: Date = .now, latestDay: String?, calendar: Calendar = .current) -> Bool {
        now >= todaysRefresh(now, calendar: calendar) && latestDay != Day.string(for: now, calendar: calendar)
    }
}
