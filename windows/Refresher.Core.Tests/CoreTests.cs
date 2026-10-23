using System.Text;
using Refresher.Core;

namespace Refresher.Core.Tests;

static class Make
{
    public static BriefItem Item(string title, SourceKind kind, double raw, string? url = null, Field field = Field.Llm) =>
        new(url ?? $"https://example.com/{kind}/{title}", title, "", kind, kind.Label(), "", raw, field: field);
}

public class CategorizerTests
{
    [Fact]
    public void Fields()
    {
        Assert.Equal(Field.Neuro, Categorizer.FieldFor("Whole-brain connectome of the fruit fly"));
        Assert.Equal(Field.Robotics, Categorizer.FieldFor("A VLA policy for humanoid manipulation"));
        Assert.Equal(Field.Audio, Categorizer.FieldFor("Streaming TTS with 80ms latency"));
        Assert.Equal(Field.Systems, Categorizer.FieldFor("FP4 inference kernels for Blackwell"));
        Assert.Equal(Field.Llm, Categorizer.FieldFor("Scaling LLMs to longer context"));
        Assert.Equal(Field.General, Categorizer.FieldFor("A new kind of spreadsheet"));
    }

    [Fact]
    public void WordBoundaries()
    {
        // "rl" must not match inside "world", "ai" not inside "said".
        Assert.Equal(Field.General, Categorizer.FieldFor("Hello world"));
        Assert.False(Categorizer.IsAIRelated("She said hello"));
        Assert.True(Categorizer.IsAIRelated("Meta reduces employee use of Claude AI"));
        Assert.True(Categorizer.IsAIRelated("Show HN: a local LLMs benchmark"));
        Assert.False(Categorizer.IsAIRelated("Margaret Hamilton has died"));
    }
}

public class RankerTests
{
    [Fact]
    public void NormalizesWithinSourceAndAppliesWeights()
    {
        var ranked = Ranker.Rank([
            Make.Item("hn-top", SourceKind.hackerNews, 900), Make.Item("hn-low", SourceKind.hackerNews, 30),
            Make.Item("paper-top", SourceKind.hfPapers, 160), Make.Item("paper-low", SourceKind.hfPapers, 2),
        ]);
        Assert.Equal(["paper-top", "hn-top", "hn-low", "paper-low"], ranked.Select(i => i.Title));
        Assert.Equal(1.0, ranked[0].Score);
        Assert.Equal(0.95, ranked[1].Score);
    }

    [Fact]
    public void CapsPerSourceAndField()
    {
        var config = new RankingConfig { PerKindCap = 2, PerFieldCap = 3 };
        var items = Enumerable.Range(1, 5).Select(i => Make.Item($"gh{i}", SourceKind.githubTrending, 100 * i, field: Field.Agents))
            .Concat(Enumerable.Range(1, 5).Select(i => Make.Item($"p{i}", SourceKind.hfPapers, i, field: Field.Agents)))
            .Append(Make.Item("robot", SourceKind.hfModels, 5, field: Field.Robotics));
        var ranked = Ranker.Rank(items, config: config);
        Assert.Equal(2, ranked.Count(i => i.Kind == SourceKind.githubTrending));
        Assert.Equal(3, ranked.Count(i => i.Field == Field.Agents));
        Assert.Contains(ranked, i => i.Title == "robot");
    }

    [Fact]
    public void DedupesAndExcludesSeen()
    {
        var a = Make.Item("repo", SourceKind.githubTrending, 10, url: "https://github.com/a/b");
        var b = Make.Item("repo", SourceKind.githubNew, 10, url: "https://www.github.com/a/b/");
        var c = Make.Item("old", SourceKind.githubTrending, 50, url: "https://github.com/old/repo");
        var ranked = Ranker.Rank([a, b, c], new HashSet<string> { "github.com/old/repo" });
        Assert.Single(ranked);
        Assert.Equal(SourceKind.githubTrending, ranked[0].Kind);
    }

    [Fact]
    public void Deterministic()
    {
        var kinds = Enum.GetValues<SourceKind>();
        var items = Enumerable.Range(1, 30).Select(i => Make.Item($"i{i}", kinds[i % 8], i % 7)).ToList();
        Assert.Equal(Ranker.Rank(items).Select(i => i.Id), Ranker.Rank(Enumerable.Reverse(items)).Select(i => i.Id));
    }
}

public class ParserTests
{
    [Fact]
    public void GithubTrendingRow()
    {
        const string html = """
            <article class="Box-row"><h2><a href="/org/llm-tool">org / llm-tool</a></h2>
            <p class="col-9 color-fg-muted my-1 tmp-pr-4">
              Fast LLM inference &amp; serving
            </p>
            <a href="/org/llm-tool/stargazers">12,710</a>
            <span class="d-inline-block float-sm-right">4,640 stars today</span></article>
            """;
        var items = GitHubTrendingSource.Parse(html);
        Assert.Single(items);
        Assert.Equal("org/llm-tool", items[0].Title);
        Assert.Equal("Fast LLM inference & serving", items[0].Summary);
        Assert.Equal(4640, items[0].RawScore);
    }

    [Fact]
    public void RssAndAtom()
    {
        const string rss = """
            <rss><channel><item><title><![CDATA[Hello <b>RSS</b>]]></title><link>https://a.com/1</link>
            <description>Body</description><pubDate>Thu, 08 Oct 2026 11:26:09 GMT</pubDate></item></channel></rss>
            """;
        const string atom = """
            <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Hi Atom</title>
            <link rel="alternate" href="https://b.com/2"/><published>2026-10-08T10:00:00Z</published>
            <summary>Sum</summary></entry></feed>
            """;
        var r = FeedParser.Parse(Encoding.UTF8.GetBytes(rss));
        var a = FeedParser.Parse(Encoding.UTF8.GetBytes(atom));
        Assert.Equal("Hello RSS", r[0].Title);
        Assert.Equal("https://a.com/1", r[0].Link);
        Assert.Equal(new DateTimeOffset(2026, 10, 8, 11, 26, 9, TimeSpan.Zero), r[0].Date);
        Assert.Equal("https://b.com/2", a[0].Link);
        Assert.NotNull(a[0].Date);
    }

    [Theory]
    [InlineData("Thu, 08 Oct 2026 11:26:09 +0000")]
    [InlineData("Thu, 8 Oct 2026 07:26:09 -0400")]
    [InlineData("Thu, 08 Oct 2026 04:26:09 PDT")]
    public void Rfc822Dates(string s) =>
        Assert.Equal(new DateTimeOffset(2026, 10, 8, 11, 26, 9, TimeSpan.Zero), FeedParser.ParseDate(s));
}

public class ScheduleAndStoreTests
{
    static readonly TimeZoneInfo Lisbon = TimeZoneInfo.FindSystemTimeZoneById("Europe/Lisbon");

    static DateTimeOffset Date(int h, int day = 8)
    {
        var local = new DateTime(2026, 10, day, h, 0, 0);
        return new DateTimeOffset(local, Lisbon.GetUtcOffset(local));
    }

    [Fact]
    public void DueOnlyAfterNoonOncePerDay()
    {
        Assert.False(Schedule.IsDue(Date(11), "2026-10-07", Lisbon));
        Assert.True(Schedule.IsDue(Date(13), "2026-10-07", Lisbon));
        Assert.False(Schedule.IsDue(Date(13), "2026-10-08", Lisbon));
        Assert.Equal(Date(12, day: 9), Schedule.NextRefresh(Date(13), Lisbon));
    }

    [Fact]
    public void CollectionRoundTripAndSeen()
    {
        var dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            var store = new BriefStore(dir);
            var a = Make.Item("a", SourceKind.blog, 1);
            store.Save(new DailyBrief("2026-10-07", DateTimeOffset.Now, [a], []));
            Assert.Equal([a.Id], store.SeenIDs(before: "2026-10-08"));
            Assert.Empty(store.SeenIDs(before: "2026-10-07"));

            Assert.True(store.Save(a));
            Assert.False(store.Save(a));
            store.UpdateCollection(items => items[0] = items[0] with { Tags = ["rl"], IsRead = true });
            var saved = new BriefStore(dir).LoadCollection();
            Assert.True(saved.Count == 1 && saved[0].Tags.SequenceEqual(["rl"]) && saved[0].IsRead);
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    /// The files are interchangeable with the macOS app's.
    [Fact]
    public void ReadsMacOSFormat()
    {
        const string json = """
            [{"isRead":false,"item":{"discussionURL":"https://arxiv.org/abs/2610.1","field":"Video & 3D","id":"huggingface.co/papers/2610.1",
              "kind":"hfPapers","metric":"9 upvotes","rawScore":9,"score":1,"source":"HF Papers","summary":"S","title":"T",
              "url":"https://huggingface.co/papers/2610.1"},"note":"n","savedAt":"2026-10-21T18:02:11Z","tags":["x"]}]
            """;
        var items = System.Text.Json.JsonSerializer.Deserialize<List<SavedItem>>(json, BriefStore.Json)!;
        Assert.Equal(Field.Video, items[0].Item.Field);
        Assert.Equal(SourceKind.hfPapers, items[0].Item.Kind);
        var back = System.Text.Json.JsonSerializer.Serialize(items, BriefStore.Json);
        Assert.Contains("\"savedAt\": \"2026-10-21T18:02:11Z\"", back);
        Assert.Contains("\"field\": \"Video & 3D\"", back);
    }
}
