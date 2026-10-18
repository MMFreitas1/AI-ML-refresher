import Foundation

public struct RankingConfig: Sendable {
    public var maxItems = 15
    /// At most this many items from one source kind, so one busy source can't take over.
    public var perKindCap = 3
    /// At most this many items from one field, so LLM news doesn't crowd out everything else.
    public var perFieldCap = 4
    /// Trust in each source's popularity signal. A source's #1 item scores exactly its weight.
    public var weights: [SourceKind: Double] = [
        .githubTrending: 1.0,
        .hfPapers: 1.0,
        .hackerNews: 0.95,
        .githubNew: 0.9,
        .hfModels: 0.9,
        .reddit: 0.85,
        .blog: 0.8,
        .hfSpaces: 0.7,
    ]

    public init() {}
}

/// Deterministic ranking: same inputs always give the same list.
///
/// 1. Drop items already shown on previous days.
/// 2. De-duplicate by canonical URL, keeping the copy from the higher-weight source.
/// 3. Within each source, score = weight × log(1 + raw) / log(1 + best raw in that source).
///    Log scaling keeps a 10k-star outlier from flattening everything else.
/// 4. Sort by score (ties: raw score, then newest, then title) and pick greedily under the caps.
public enum Ranker {
    public static func rank(_ items: [BriefItem], excluding seen: Set<String> = [],
                            config: RankingConfig = RankingConfig()) -> [BriefItem] {
        let weight = { (k: SourceKind) in config.weights[k] ?? 0.5 }

        var byID: [String: BriefItem] = [:]
        for item in items where !seen.contains(item.id) {
            if let existing = byID[item.id], weight(existing.kind) >= weight(item.kind) { continue }
            byID[item.id] = item
        }

        let grouped = Dictionary(grouping: byID.values, by: \.kind)
        var scored: [BriefItem] = []
        for (kind, group) in grouped {
            let best = group.map(\.rawScore).max() ?? 0
            for var item in group {
                let relative = best > 0 ? log1p(max(item.rawScore, 0)) / log1p(best) : 1
                item.score = weight(kind) * relative
                scored.append(item)
            }
        }

        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.rawScore != b.rawScore { return a.rawScore > b.rawScore }
            let da = a.publishedAt ?? .distantPast, db = b.publishedAt ?? .distantPast
            if da != db { return da > db }
            return a.title < b.title
        }

        var picked: [BriefItem] = []
        var kindCount: [SourceKind: Int] = [:]
        var fieldCount: [Field: Int] = [:]
        for item in scored where picked.count < config.maxItems {
            guard kindCount[item.kind, default: 0] < config.perKindCap,
                  fieldCount[item.field, default: 0] < config.perFieldCap else { continue }
            picked.append(item)
            kindCount[item.kind, default: 0] += 1
            fieldCount[item.field, default: 0] += 1
        }
        return picked
    }
}
