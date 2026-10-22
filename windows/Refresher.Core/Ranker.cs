namespace Refresher.Core;

public sealed record RankingConfig
{
    public int MaxItems { get; init; } = 15;
    /// <summary>At most this many items from one source kind, so one busy source can't take over.</summary>
    public int PerKindCap { get; init; } = 3;
    /// <summary>At most this many items from one field, so LLM news doesn't crowd out everything else.</summary>
    public int PerFieldCap { get; init; } = 4;
    /// <summary>Trust in each source's popularity signal. A source's #1 item scores exactly its weight.</summary>
    public IReadOnlyDictionary<SourceKind, double> Weights { get; init; } = new Dictionary<SourceKind, double>
    {
        [SourceKind.githubTrending] = 1.0,
        [SourceKind.hfPapers] = 1.0,
        [SourceKind.hackerNews] = 0.95,
        [SourceKind.githubNew] = 0.9,
        [SourceKind.hfModels] = 0.9,
        [SourceKind.reddit] = 0.85,
        [SourceKind.blog] = 0.8,
        [SourceKind.hfSpaces] = 0.7,
    };
}

/// <summary>
/// Deterministic ranking: same inputs always give the same list. Same formula as the macOS app.
///
/// 1. Drop items already shown on previous days.
/// 2. De-duplicate by canonical URL, keeping the copy from the higher-weight source.
/// 3. Within each source, score = weight × log(1 + raw) / log(1 + best raw in that source).
///    Log scaling keeps a 10k-star outlier from flattening everything else.
/// 4. Sort by score (ties: raw score, then newest, then title) and pick greedily under the caps.
/// </summary>
public static class Ranker
{
    public static List<BriefItem> Rank(IEnumerable<BriefItem> items, IReadOnlySet<string>? seen = null,
                                       RankingConfig? config = null)
    {
        config ??= new RankingConfig();
        double Weight(SourceKind k) => config.Weights.TryGetValue(k, out var w) ? w : 0.5;

        var byID = new Dictionary<string, BriefItem>();
        foreach (var item in items)
        {
            if (seen?.Contains(item.Id) == true) continue;
            if (byID.TryGetValue(item.Id, out var existing) && Weight(existing.Kind) >= Weight(item.Kind)) continue;
            byID[item.Id] = item;
        }

        var scored = new List<BriefItem>();
        foreach (var group in byID.Values.GroupBy(i => i.Kind))
        {
            var best = group.Max(i => i.RawScore);
            foreach (var item in group)
            {
                var relative = best > 0 ? Math.Log(1 + Math.Max(item.RawScore, 0)) / Math.Log(1 + best) : 1;
                scored.Add(item with { Score = Weight(group.Key) * relative });
            }
        }

        scored.Sort((a, b) =>
        {
            if (a.Score != b.Score) return b.Score.CompareTo(a.Score);
            if (a.RawScore != b.RawScore) return b.RawScore.CompareTo(a.RawScore);
            var da = a.PublishedAt ?? DateTimeOffset.MinValue;
            var db = b.PublishedAt ?? DateTimeOffset.MinValue;
            if (da != db) return db.CompareTo(da);
            return string.CompareOrdinal(a.Title, b.Title);
        });

        var picked = new List<BriefItem>();
        var kindCount = new Dictionary<SourceKind, int>();
        var fieldCount = new Dictionary<Field, int>();
        foreach (var item in scored)
        {
            if (picked.Count >= config.MaxItems) break;
            if (kindCount.GetValueOrDefault(item.Kind) >= config.PerKindCap
                || fieldCount.GetValueOrDefault(item.Field) >= config.PerFieldCap) continue;
            picked.Add(item);
            kindCount[item.Kind] = kindCount.GetValueOrDefault(item.Kind) + 1;
            fieldCount[item.Field] = fieldCount.GetValueOrDefault(item.Field) + 1;
        }
        return picked;
    }
}
