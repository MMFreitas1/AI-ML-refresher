namespace Refresher.Core;

public sealed class BriefBuilder
{
    public static IBriefSource[] DefaultSources() =>
    [
        new GitHubTrendingSource(), new GitHubNewReposSource(), new HFPapersSource(), new HFModelsSource(),
        new HFSpacesSource(), new HackerNewsSource(), new RedditSource(), new BlogSource(),
    ];

    public IBriefSource[] Sources { get; init; } = DefaultSources();
    public RankingConfig Config { get; init; } = new();
    public Http Http { get; init; } = new();

    /// <summary>Fetches every source in parallel, ranks, and saves today's brief.
    /// Failing sources are recorded in Errors instead of failing the whole run.</summary>
    public async Task<DailyBrief> Run(BriefStore store, DateTimeOffset? now = null, CancellationToken ct = default)
    {
        var at = now ?? DateTimeOffset.Now;
        var (candidates, errors) = await FetchAll(at, ct);
        var day = Day.String(at);
        var items = Ranker.Rank(candidates, store.SeenIDs(before: day), Config);
        var brief = new DailyBrief(day, at, items, errors);
        // Don't replace a good brief with an empty one when offline.
        if (items.Count == 0 && store.Brief(day) is { Items.Count: > 0 } existing) return existing;
        store.Save(brief);
        return brief;
    }

    public async Task<(List<BriefItem> Items, List<string> Errors)> FetchAll(DateTimeOffset now, CancellationToken ct = default)
    {
        var results = await Task.WhenAll(Sources.Select(async source =>
        {
            try { return (Items: await source.Fetch(Http, now, ct), Error: (string?)null); }
            catch (Exception e) when (!ct.IsCancellationRequested)
            {
                var message = e is TaskCanceledException ? "timed out" : e.Message;
                return (Items: new List<BriefItem>(), Error: $"{source.Name}: {message}");
            }
        }));
        return (results.SelectMany(r => r.Items).ToList(),
                results.Select(r => r.Error).OfType<string>().Order(StringComparer.Ordinal).ToList());
    }
}

/// <summary>When a new brief is due: once per day, at or after 12:00 local time.</summary>
public static class Schedule
{
    public const int RefreshHour = 12;

    public static DateTimeOffset TodaysRefresh(DateTimeOffset now, TimeZoneInfo? zone = null)
    {
        zone ??= TimeZoneInfo.Local;
        var local = TimeZoneInfo.ConvertTime(now, zone);
        var noon = new DateTime(local.Year, local.Month, local.Day, RefreshHour, 0, 0, DateTimeKind.Unspecified);
        return new DateTimeOffset(noon, zone.GetUtcOffset(noon));
    }

    public static DateTimeOffset NextRefresh(DateTimeOffset now, TimeZoneInfo? zone = null)
    {
        var today = TodaysRefresh(now, zone);
        return now < today ? today : TodaysRefresh(today.AddDays(1), zone);
    }

    /// <summary>True after noon when today's brief hasn't been built yet (also covers a PC asleep at noon).</summary>
    public static bool IsDue(DateTimeOffset now, string? latestDay, TimeZoneInfo? zone = null) =>
        now >= TodaysRefresh(now, zone) && latestDay != Day.String(now, zone);
}
