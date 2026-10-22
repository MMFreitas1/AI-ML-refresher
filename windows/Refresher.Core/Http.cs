using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Refresher.Core;

public sealed class Http
{
    static readonly HttpClient Shared = new(new SocketsHttpHandler { AutomaticDecompression = DecompressionMethods.All })
    {
        Timeout = TimeSpan.FromSeconds(30),
    };

    public string UserAgent { get; init; } = "AI-ML-Refresher/1.0 (+https://github.com/MMFreitas1/AI-ML-refresher)";
    /// <summary>Optional, raises GitHub's search rate limit. Read from the GITHUB_TOKEN environment variable.</summary>
    public string? GithubToken { get; init; } = Environment.GetEnvironmentVariable("GITHUB_TOKEN");

    public async Task<byte[]> Data(string url, IReadOnlyDictionary<string, string>? headers = null, CancellationToken ct = default)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
        foreach (var (k, v) in headers ?? new Dictionary<string, string>()) req.Headers.TryAddWithoutValidation(k, v);
        using var res = await Shared.SendAsync(req, ct);
        if (!res.IsSuccessStatusCode) throw FetchError.Status((int)res.StatusCode, new Uri(url).Host);
        return await res.Content.ReadAsByteArrayAsync(ct);
    }

    public async Task<string> Text(string url, CancellationToken ct = default) =>
        System.Text.Encoding.UTF8.GetString(await Data(url, ct: ct));

    public async Task<JsonElement> Json(string url, IReadOnlyDictionary<string, string>? headers = null, CancellationToken ct = default)
    {
        var bytes = await Data(url, headers, ct);
        try { return JsonDocument.Parse(bytes).RootElement; }
        catch (JsonException) { throw FetchError.Parse($"JSON from {new Uri(url).Host}"); }
    }
}

public sealed class FetchError(string message) : Exception(message)
{
    public static FetchError Status(int code, string host) =>
        new(code == 429 ? $"{host} rate-limited the request (HTTP 429)" : $"{host} returned HTTP {code}");

    public static FetchError Parse(string what) => new($"Could not parse {what}");
}

public static class Iso8601
{
    public static DateTimeOffset? Parse(string? s) =>
        DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var d) ? d : null;
}

public static partial class Format
{
    /// <summary>12345 → "12.3k"</summary>
    public static string Compact(double n) => n switch
    {
        >= 1_000_000 => (n / 1_000_000).ToString("0.0", CultureInfo.InvariantCulture) + "M",
        >= 10_000 => (n / 1_000).ToString("0", CultureInfo.InvariantCulture) + "k",
        >= 1_000 => (n / 1_000).ToString("0.0", CultureInfo.InvariantCulture) + "k",
        _ => ((int)n).ToString(CultureInfo.InvariantCulture),
    };

    public static string StripHTML(string html)
    {
        var s = Tags().Replace(html, " ");
        foreach (var (entity, ch) in new[] { ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                              ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " "), ("&#32;", " ") })
            s = s.Replace(entity, ch);
        return Spaces().Replace(s, " ").Trim();
    }

    public static string Truncate(string s, int n = 240) => s.Length <= n ? s : s[..n].Trim() + "…";

    [GeneratedRegex("<[^>]+>")] private static partial Regex Tags();
    [GeneratedRegex(@"\s+")] private static partial Regex Spaces();
}

/// <summary>Null-tolerant readers for the loosely typed JSON the sources return.</summary>
static class JsonExt
{
    public static string? Str(this JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    public static double? Num(this JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;

    public static JsonElement? Obj(this JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind != JsonValueKind.Null ? v : null;

    public static IEnumerable<string> Strings(this JsonElement e, string name) =>
        e.Obj(name) is { ValueKind: JsonValueKind.Array } a
            ? a.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!)
            : [];
}
