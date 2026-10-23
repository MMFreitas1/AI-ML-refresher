using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Refresher.Core;

public interface IBriefSource
{
    string Name { get; }
    Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default);
}

// MARK: - GitHub

/// <summary>github.com/trending (no official API). Ranked by "stars today", AI repos only.</summary>
public sealed partial class GitHubTrendingSource : IBriefSource
{
    public string Name => "GitHub Trending";
    /// <summary>The overall page plus Python, where most ML repos live.</summary>
    public string[] Pages { get; init; } = ["https://github.com/trending?since=daily", "https://github.com/trending/python?since=daily"];

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var items = new List<BriefItem>();
        foreach (var page in Pages) items.AddRange(Parse(await http.Text(page, ct)));
        if (items.Count == 0) throw FetchError.Parse("GitHub trending page (layout may have changed)");
        return items.Where(i => Categorizer.IsAIRelated($"{i.Title} {i.Summary}")).ToList();
    }

    public static List<BriefItem> Parse(string html) =>
        html.Split("<article class=\"Box-row\">").Skip(1).Select(row =>
        {
            var repo = Stargazers().Match(row);
            if (!repo.Success) return null;
            var description = Description().Match(row) is { Success: true } d ? Format.StripHTML(d.Groups[1].Value) : "";
            var today = StarsToday().Match(row) is { Success: true } s
                ? double.Parse(s.Groups[1].Value.Replace(",", ""), CultureInfo.InvariantCulture) : 0;
            return new BriefItem($"https://github.com/{repo.Groups[1].Value}", repo.Groups[1].Value, description,
                                 SourceKind.githubTrending, "GitHub Trending", $"{Format.Compact(today)}★ today", today);
        }).OfType<BriefItem>().ToList();

    [GeneratedRegex("href=\"/([^/\"]+/[^/\"]+)/stargazers\"")] private static partial Regex Stargazers();
    [GeneratedRegex("<p class=\"col-9[^\"]*\">([\\s\\S]*?)</p>")] private static partial Regex Description();
    [GeneratedRegex(@"([\d,]+) stars? today")] private static partial Regex StarsToday();
}

/// <summary>Repos created in the last two weeks under ML topics, ranked by stars per day of age.</summary>
public sealed class GitHubNewReposSource : IBriefSource
{
    public string Name => "New on GitHub";
    public string[] Topics { get; init; } = ["llm", "machine-learning", "deep-learning", "computer-vision",
                                             "reinforcement-learning", "robotics", "ai-agents"];
    public int WindowDays { get; init; } = 14;

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var since = Day.String(now.AddDays(-WindowDays));
        var headers = new Dictionary<string, string> { ["Accept"] = "application/vnd.github+json" };
        if (http.GithubToken is { Length: > 0 } token) headers["Authorization"] = $"Bearer {token}";

        var repos = new Dictionary<string, JsonElement>();
        foreach (var topic in Topics)
        {
            var q = Uri.EscapeDataString($"topic:{topic} created:>={since}");
            var json = await http.Json($"https://api.github.com/search/repositories?q={q}&sort=stars&order=desc&per_page=10", headers, ct);
            foreach (var repo in json.GetProperty("items").EnumerateArray())
                if (repo.Str("full_name") is { } name) repos[name] = repo;
        }
        return repos.Values.Select(r =>
        {
            var name = r.Str("full_name")!;
            var description = r.Str("description") ?? "";
            var stars = r.Num("stargazers_count") ?? 0;
            var created = Iso8601.Parse(r.Str("created_at")) ?? now;
            var days = Math.Max((now - created).TotalDays, 1);
            var topics = string.Join(' ', r.Strings("topics"));
            return new BriefItem(r.Str("html_url") ?? $"https://github.com/{name}", name, description,
                                 SourceKind.githubNew, "New on GitHub", $"{Format.Compact(stars)}★ in {(int)Math.Ceiling(days)}d",
                                 stars / days, field: Categorizer.FieldFor($"{name} {description} {topics}"), publishedAt: created);
        }).ToList();
    }
}

// MARK: - Hugging Face

/// <summary>Community-upvoted papers (successor of Papers with Code). Uses the latest complete day.</summary>
public sealed class HFPapersSource : IBriefSource
{
    public string Name => "HF Papers";

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        // Yesterday's list has had a full day of votes. Weekends can be sparse, so step back if needed.
        for (var daysBack = 1; daysBack <= 4; daysBack++)
        {
            var day = Day.String(now.AddDays(-daysBack), TimeZoneInfo.Utc);
            var entries = await http.Json($"https://huggingface.co/api/daily_papers?date={day}&limit=100", ct: ct);
            if (entries.GetArrayLength() < 5) continue;
            return entries.EnumerateArray().Select(e => e.Obj("paper")).OfType<JsonElement>().Select(p =>
            {
                var id = p.Str("id") ?? "";
                var votes = p.Num("upvotes") ?? 0;
                return new BriefItem($"https://huggingface.co/papers/{id}", p.Str("title") ?? id,
                                     Format.Truncate(p.Str("summary") ?? ""), SourceKind.hfPapers, "HF Papers",
                                     $"{(int)votes} upvotes", votes, discussionURL: $"https://arxiv.org/abs/{id}",
                                     publishedAt: Iso8601.Parse(p.Str("publishedAt")));
            }).ToList();
        }
        return [];
    }
}

public sealed class HFModelsSource : IBriefSource
{
    public string Name => "HF Models";

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var models = await http.Json("https://huggingface.co/api/models?sort=trendingScore&limit=25", ct: ct);
        return models.EnumerateArray().Select(m =>
        {
            var id = m.Str("id") ?? "";
            var task = m.Str("pipeline_tag") ?? "model";
            var likes = m.Num("likes");
            var summary = string.Join(" · ", new[] { task, m.Str("library_name"), likes is { } l ? $"{Format.Compact(l)} likes" : null }
                                              .OfType<string>());
            var trending = m.Num("trendingScore") ?? 0;
            return new BriefItem($"https://huggingface.co/{id}", id, summary, SourceKind.hfModels, "HF Models",
                                 $"trending {(int)trending}", trending,
                                 field: HFTask.FieldFor(task) ?? Categorizer.FieldFor($"{id} {string.Join(' ', m.Strings("tags"))}"),
                                 publishedAt: Iso8601.Parse(m.Str("createdAt")));
        }).ToList();
    }
}

public sealed class HFSpacesSource : IBriefSource
{
    public string Name => "HF Spaces";

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var spaces = await http.Json("https://huggingface.co/api/spaces?sort=trendingScore&limit=25&expand[]=cardData&expand[]=likes&expand[]=trendingScore&expand[]=createdAt", ct: ct);
        return spaces.EnumerateArray().Select(s =>
        {
            var id = s.Str("id") ?? "";
            var card = s.Obj("cardData");
            var title = card?.Str("title") is { } t ? $"{t} ({id})" : id;
            var trending = s.Num("trendingScore") ?? 0;
            return new BriefItem($"https://huggingface.co/spaces/{id}", title, card?.Str("short_description") ?? "Hugging Face Space",
                                 SourceKind.hfSpaces, "HF Spaces", $"trending {(int)trending}", trending,
                                 publishedAt: Iso8601.Parse(s.Str("createdAt")));
        }).ToList();
    }
}

static class HFTask
{
    public static Field? FieldFor(string t)
    {
        if (t.Contains("video") || t.Contains("3d")) return Field.Video;
        if (t.Contains("audio") || t.Contains("speech") || t.Contains("voice")) return Field.Audio;
        if (t.Contains("image") || t.Contains("object-detection") || t.Contains("depth")
            || t.Contains("segmentation") || t.Contains("visual")) return Field.Vision;
        return t switch
        {
            "robotics" => Field.Robotics,
            "reinforcement-learning" => Field.Rl,
            "text-generation" or "text2text-generation" or "feature-extraction" or "sentence-similarity"
                or "text-classification" or "translation" or "summarization" or "fill-mask" or "token-classification" => Field.Llm,
            _ => null,
        };
    }
}

// MARK: - Community

/// <summary>Hacker News stories from the last 24h that mention AI/ML, ranked by points.</summary>
public sealed class HackerNewsSource : IBriefSource
{
    public string Name => "Hacker News";
    public int MinPoints { get; init; } = 30;

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var since = now.ToUnixTimeSeconds() - 86_400;
        var filters = Uri.EscapeDataString($"created_at_i>{since},points>{MinPoints}");
        var json = await http.Json($"https://hn.algolia.com/api/v1/search?tags=story&numericFilters={filters}&hitsPerPage=200", ct: ct);
        return json.GetProperty("hits").EnumerateArray().Select(h =>
        {
            var title = h.Str("title");
            if (title == null || !Categorizer.IsAIRelated(title)) return null;
            var discussion = $"https://news.ycombinator.com/item?id={h.Str("objectID")}";
            var url = h.Str("url") is { } u && Uri.TryCreate(u, UriKind.Absolute, out _) ? u : discussion;
            var points = h.Num("points") ?? 0;
            return new BriefItem(url, title, $"via {new Uri(url).Host}", SourceKind.hackerNews, "Hacker News",
                                 $"{(int)points} pts · {(int)(h.Num("num_comments") ?? 0)} comments", points,
                                 discussionURL: discussion,
                                 publishedAt: DateTimeOffset.FromUnixTimeSeconds((long)(h.Num("created_at_i") ?? 0)));
        }).OfType<BriefItem>().ToList();
    }
}

/// <summary>Reddit's daily top posts via RSS. The feed carries no scores, so rank order is the signal.
/// Reddit rate-limits anonymous clients hard, hence few subreddits and a pause between them.</summary>
public sealed partial class RedditSource : IBriefSource
{
    public string Name => "Reddit";
    public string[] Subreddits { get; init; } = ["MachineLearning", "LocalLLaMA"];
    public int PerSub { get; init; } = 10;

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var items = new List<BriefItem>();
        Exception? lastError = null;
        for (var i = 0; i < Subreddits.Length; i++)
        {
            var sub = Subreddits[i];
            if (i > 0) await Task.Delay(TimeSpan.FromSeconds(3), ct);
            List<FeedEntry> entries;
            try { entries = FeedParser.Parse(await http.Data($"https://www.reddit.com/r/{sub}/top/.rss?t=day&limit={PerSub}", ct: ct)).Take(PerSub).ToList(); }
            catch (Exception e) when (e is not OperationCanceledException) { lastError = e; continue; }
            for (var rank = 0; rank < entries.Count; rank++)
            {
                var e = entries[rank];
                if (!Uri.TryCreate(e.Link, UriKind.Absolute, out _)) continue;
                items.Add(new BriefItem(e.Link, e.Title, Format.Truncate(SubmittedBy().Replace(e.Summary, "")),
                                        SourceKind.reddit, $"r/{sub}", $"#{rank + 1} today on r/{sub}",
                                        PerSub - rank, publishedAt: e.Date));
            }
        }
        if (items.Count == 0 && lastError != null) throw lastError;
        return items;
    }

    [GeneratedRegex("submitted by.*$", RegexOptions.Singleline)] private static partial Regex SubmittedBy();
}

// MARK: - Blogs & newsletters

/// <summary>Curated writing. Feeds carry no popularity signal, so every new post scores equally
/// and the newest win ties. Only posts from the last <see cref="WindowHours"/> count as new.</summary>
public sealed class BlogSource : IBriefSource
{
    /// <param name="AiOnly">For general-purpose feeds, keep only AI-related posts.</param>
    /// <param name="FieldHint">Field to use when the keyword rules find nothing specific.</param>
    public sealed record Feed(string Name, string Url, bool AiOnly = false, Field? FieldHint = null);

    public string Name => "Blogs";
    public double WindowHours { get; init; } = 48;

    public static readonly Feed[] DefaultFeeds =
    [
        new("Import AI", "https://importai.substack.com/feed"),
        new("Latent Space", "https://www.latent.space/feed"),
        new("Interconnects", "https://www.interconnects.ai/feed"),
        new("Ahead of AI", "https://magazine.sebastianraschka.com/feed"),
        new("Last Week in AI", "https://lastweekin.ai/feed"),
        new("Simon Willison", "https://simonwillison.net/atom/entries/", AiOnly: true),
        new("Google DeepMind", "https://deepmind.google/blog/rss.xml"),
        new("OpenAI", "https://openai.com/news/rss.xml"),
        new("Hugging Face Blog", "https://huggingface.co/blog/feed.xml"),
        new("BAIR", "https://bair.berkeley.edu/blog/feed.xml"),
        new("NVIDIA", "https://blogs.nvidia.com/feed/", AiOnly: true),
        new("The Robot Report", "https://www.therobotreport.com/feed/", FieldHint: Field.Robotics),
        new("The Transmitter", "https://www.thetransmitter.org/feed/", FieldHint: Field.Neuro),
    ];

    public Feed[] Feeds { get; init; } = DefaultFeeds;

    public async Task<List<BriefItem>> Fetch(Http http, DateTimeOffset now, CancellationToken ct = default)
    {
        var cutoff = now.AddHours(-WindowHours);
        var results = await Task.WhenAll(Feeds.Select(async feed =>
        {
            try
            {
                var entries = FeedParser.Parse(await http.Data(feed.Url, ct: ct));
                return (Items: entries.Select(e =>
                {
                    if (e.Date is not { } date || date < cutoff || date > now.AddHours(1)
                        || !Uri.TryCreate(e.Link, UriKind.Absolute, out _)) return null;
                    if (feed.AiOnly && !Categorizer.IsAIRelated($"{e.Title} {e.Summary}")) return null;
                    var field = Categorizer.FieldFor($"{e.Title} {e.Summary}");
                    if (field == Field.General && feed.FieldHint is { } hint) field = hint;
                    return new BriefItem(e.Link, e.Title, Format.Truncate(e.Summary), SourceKind.blog, feed.Name,
                                         feed.Name, 1, field: field, publishedAt: date);
                }).OfType<BriefItem>().ToList(), Error: (string?)null);
            }
            catch (Exception e) when (e is not OperationCanceledException || !ct.IsCancellationRequested)
            {
                return (Items: new List<BriefItem>(), Error: $"{feed.Name}: {e.Message}");
            }
        }));
        var items = results.SelectMany(r => r.Items).ToList();
        var failures = results.Select(r => r.Error).OfType<string>().ToList();
        // A single dead feed shouldn't sink the others; only fail when everything failed.
        if (items.Count == 0 && failures.Count == Feeds.Length)
            throw FetchError.Parse($"all blog feeds ({failures.FirstOrDefault()})");
        return items;
    }
}
