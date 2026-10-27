using System.Text.Json.Serialization;

namespace Refresher.Core;

/// <summary>Broad research area an item belongs to. Assigned by deterministic keyword rules (see <see cref="Categorizer"/>).</summary>
[JsonConverter(typeof(FieldConverter))]
public enum Field { Llm, Agents, Vision, Video, Audio, Robotics, Rl, Neuro, Systems, General }

public static class FieldInfo
{
    /// <summary>Display name. Also the stored value, matching the macOS app's JSON.</summary>
    public static string Label(this Field f) => f switch
    {
        Field.Llm => "LLMs & NLP",
        Field.Agents => "Agents",
        Field.Vision => "Vision",
        Field.Video => "Video & 3D",
        Field.Audio => "Audio & Speech",
        Field.Robotics => "Robotics",
        Field.Rl => "Reinforcement Learning",
        Field.Neuro => "Neuroscience",
        Field.Systems => "Systems & Infra",
        _ => "General AI",
    };

    public static Field? FromLabel(string label) =>
        Enum.GetValues<Field>().Cast<Field?>().FirstOrDefault(f => f!.Value.Label() == label);
}

/// <summary>Where an item came from. Each kind is ranked within itself before items are merged.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SourceKind>))]
public enum SourceKind { githubTrending, githubNew, hfPapers, hfModels, hfSpaces, hackerNews, reddit, blog }

public static class SourceKindInfo
{
    public static string Label(this SourceKind k) => k switch
    {
        SourceKind.githubTrending => "GitHub Trending",
        SourceKind.githubNew => "New on GitHub",
        SourceKind.hfPapers => "HF Papers",
        SourceKind.hfModels => "HF Models",
        SourceKind.hfSpaces => "HF Spaces",
        SourceKind.hackerNews => "Hacker News",
        SourceKind.reddit => "Reddit",
        _ => "Blogs",
    };
}

public sealed record BriefItem
{
    /// <summary>Canonical URL, used for de-duplication across sources and days.</summary>
    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string Summary { get; init; } = "";
    public string Url { get; init; } = "";
    public string? DiscussionURL { get; init; }
    public SourceKind Kind { get; init; }
    /// <summary>Specific origin, e.g. "r/LocalLLaMA" or "Import AI".</summary>
    public string Source { get; init; } = "";
    /// <summary>Human readable popularity signal, e.g. "4,640★ today".</summary>
    public string Metric { get; init; } = "";
    /// <summary>Popularity signal used for ranking inside its source (stars, upvotes, points…).</summary>
    public double RawScore { get; init; }
    /// <summary>Normalized cross-source score in 0...1, set by <see cref="Ranker"/>.</summary>
    public double Score { get; init; }
    public Field Field { get; init; }
    public DateTimeOffset? PublishedAt { get; init; }

    public BriefItem() { }

    public BriefItem(string url, string title, string summary, SourceKind kind, string source,
                     string metric, double rawScore, string? discussionURL = null,
                     Field? field = null, DateTimeOffset? publishedAt = null)
    {
        Id = Canonical.Id(url);
        Title = title.Trim();
        Summary = summary.Trim();
        Url = url;
        DiscussionURL = discussionURL;
        Kind = kind;
        Source = source;
        Metric = metric;
        RawScore = rawScore;
        Field = field ?? Categorizer.FieldFor($"{title} {summary}");
        PublishedAt = publishedAt;
    }
}

/// <param name="Day">Local calendar day, yyyy-MM-dd.</param>
/// <param name="Errors">Sources that failed during this run, shown in the UI so silent gaps are visible.</param>
public sealed record DailyBrief(string Day, DateTimeOffset GeneratedAt, IReadOnlyList<BriefItem> Items, IReadOnlyList<string> Errors);

public sealed record SavedItem
{
    public required BriefItem Item { get; init; }
    public DateTimeOffset SavedAt { get; init; } = SyncClock.Now;
    public List<string> Tags { get; init; } = [];
    public string Note { get; init; } = "";
    public bool IsRead { get; init; }
    /// <summary>Last change to tags, note or read state, for syncing. Absent in files from before sync: then SavedAt.</summary>
    public DateTimeOffset? UpdatedAt { get; init; }

    [JsonIgnore] public string Id => Item.Id;
    [JsonIgnore] public DateTimeOffset ChangedAt => UpdatedAt ?? SavedAt;
}

public static class Canonical
{
    /// <summary>Lowercased host+path without scheme, www., query, fragment or trailing slash.</summary>
    public static string Id(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return url.ToLowerInvariant();
        var host = uri.Host.ToLowerInvariant();
        if (host.StartsWith("www.")) host = host[4..];
        var path = Uri.UnescapeDataString(uri.AbsolutePath).TrimEnd('/');
        // arXiv abs/pdf links point at the same paper.
        if (host == "arxiv.org") path = path.Replace("/pdf/", "/abs/");
        return host + path.ToLowerInvariant();
    }
}

public static class Day
{
    /// <summary>yyyy-MM-dd in the given time zone (the user's local one by default).</summary>
    public static string String(DateTimeOffset date, TimeZoneInfo? zone = null) =>
        TimeZoneInfo.ConvertTime(date, zone ?? TimeZoneInfo.Local).ToString("yyyy-MM-dd");
}
