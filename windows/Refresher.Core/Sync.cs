using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Refresher.Core;

/// <summary>Seconds precision, like the stored dates, so a value compares equal after a round trip.</summary>
public static class SyncClock
{
    public static DateTimeOffset Now
    {
        get
        {
            var now = DateTimeOffset.UtcNow;
            return now.AddTicks(-(now.Ticks % TimeSpan.TicksPerSecond));
        }
    }
}

/// <summary>A collection plus its removals: what is synced.</summary>
public sealed record SyncSnapshot(List<SavedItem> Items, Dictionary<string, DateTimeOffset> Deleted)
{
    public SyncSnapshot() : this([], []) { }

    /// <summary>Content comparison, independent of item order.</summary>
    public bool SameAs(SyncSnapshot other) => Key(this) == Key(other);

    static string Key(SyncSnapshot s) => string.Join("\n",
        s.Items.OrderBy(i => i.Id, StringComparer.Ordinal).Select(BriefStore.Fingerprint)
            .Concat(s.Deleted.OrderBy(d => d.Key, StringComparer.Ordinal).Select(d => $"{d.Key}={d.Value.ToUnixTimeSeconds()}")));
}

/// <summary>
/// Merging two copies of the collection (this device's and the synced file). Same rules in the
/// macOS and Android apps, so any device can merge with any other:
///
/// - Per item, the copy changed last (UpdatedAt, else SavedAt) wins. Ties keep the first argument's.
/// - A removal wins over copies changed at or before it; an item saved again later comes back.
/// - Removal times are kept (the latest per item) so a removal reaches devices that sync later.
/// - The result is ordered newest saved first, like the collection itself.
/// </summary>
public static class CollectionSync
{
    public static SyncSnapshot Merge(SyncSnapshot local, SyncSnapshot remote)
    {
        var deleted = new Dictionary<string, DateTimeOffset>(local.Deleted);
        foreach (var (id, at) in remote.Deleted)
            deleted[id] = deleted.TryGetValue(id, out var existing) && existing > at ? existing : at;

        var byID = new Dictionary<string, SavedItem>();
        foreach (var item in local.Items.Concat(remote.Items))
            if (!byID.TryGetValue(item.Id, out var existing) || item.ChangedAt > existing.ChangedAt) byID[item.Id] = item;

        var items = byID.Values
            .Where(i => !deleted.TryGetValue(i.Id, out var at) || i.ChangedAt > at)
            .OrderByDescending(i => i.SavedAt).ThenBy(i => i.Id, StringComparer.Ordinal).ToList();
        // An item that outlived its removal no longer needs the removal record.
        foreach (var i in items) deleted.Remove(i.Id);
        return new SyncSnapshot(items, new SortedDictionary<string, DateTimeOffset>(deleted, StringComparer.Ordinal)
            .ToDictionary(d => d.Key, d => d.Value));
    }
}

/// <summary>Where the synced copy lives. <see cref="DriveFile"/> in the app; a fake in tests.</summary>
public interface IRemoteCollection
{
    Task<string?> Find(CancellationToken ct = default);
    Task<SyncSnapshot> Read(string id, CancellationToken ct = default);
    Task<string> Create(SyncSnapshot snapshot, CancellationToken ct = default);
    Task Update(string id, SyncSnapshot snapshot, CancellationToken ct = default);
}

/// <summary>One sync: download the synced copy, merge it into the local collection, upload the result if it changed.</summary>
public sealed class CollectionSyncer(BriefStore store, IRemoteCollection remote)
{
    /// <param name="ChangedLocally">The local collection changed (reload the UI).</param>
    public sealed record Outcome(int Items, bool Uploaded, bool ChangedLocally);

    public async Task<Outcome> Sync(CancellationToken ct = default)
    {
        var id = await remote.Find(ct);
        var theirs = id is null ? new SyncSnapshot() : await remote.Read(id, ct);
        var before = new SyncSnapshot(store.LoadCollection(), store.LoadDeleted());
        var merged = store.MergeCollection(theirs);
        var upload = id is null || !merged.SameAs(theirs);
        if (upload)
        {
            if (id is null) await remote.Create(merged, ct);
            else await remote.Update(id, merged, ct);
        }
        return new Outcome(merged.Items.Count, upload, !merged.SameAs(before));
    }
}

/// <summary>The Google sign-in has expired or was revoked: sign in again.</summary>
public sealed class DriveAuthException(string message) : Exception(message);

/// <summary>
/// The synced copy of the collection: one JSON file (<see cref="SyncSnapshot"/>) in the user's Google Drive.
/// Uses only the drive.file permission (files the app created, nothing else). The file is found by an
/// app property rather than its name, so renaming or moving it in Drive doesn't break syncing.
/// </summary>
/// <param name="accessToken">Returns a current OAuth access token for the signed-in Google account.</param>
public sealed class DriveFile(Func<CancellationToken, Task<string>> accessToken) : IRemoteCollection
{
    public const string Scope = "https://www.googleapis.com/auth/drive.file";
    public const string FileName = "AI-ML Refresher library.json";
    const string Property = "refresherCollection";
    const string Api = "https://www.googleapis.com/drive/v3";
    const string Upload = "https://www.googleapis.com/upload/drive/v3";
    static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(30) };

    public async Task<string?> Find(CancellationToken ct = default)
    {
        var q = Uri.EscapeDataString($"appProperties has {{ key='{Property}' and value='1' }} and trashed=false");
        using var doc = JsonDocument.Parse(await Send(HttpMethod.Get, $"{Api}/files?spaces=drive&fields=files(id)&orderBy=createdTime&q={q}", null, ct));
        var files = doc.RootElement.GetProperty("files");
        return files.GetArrayLength() > 0 ? files[0].GetProperty("id").GetString() : null;
    }

    public async Task<SyncSnapshot> Read(string id, CancellationToken ct = default)
    {
        var body = await Send(HttpMethod.Get, $"{Api}/files/{id}?alt=media", null, ct);
        try { return JsonSerializer.Deserialize<SyncSnapshot>(body, BriefStore.Json) ?? new(); }
        catch (JsonException) { throw FetchError.Parse("the synced collection"); }
    }

    public async Task<string> Create(SyncSnapshot snapshot, CancellationToken ct = default)
    {
        var metadata = new StringContent(
            $$$"""{"name":"{{{FileName}}}","mimeType":"application/json","appProperties":{"{{{Property}}}":"1"}}""",
            Encoding.UTF8, "application/json");
        var content = new MultipartContent("related") { metadata, Json(snapshot) };
        using var doc = JsonDocument.Parse(await Send(HttpMethod.Post, $"{Upload}/files?uploadType=multipart&fields=id", content, ct));
        return doc.RootElement.GetProperty("id").GetString() ?? throw FetchError.Parse("Google Drive's reply");
    }

    public Task Update(string id, SyncSnapshot snapshot, CancellationToken ct = default) =>
        Send(HttpMethod.Patch, $"{Upload}/files/{id}?uploadType=media&fields=id", Json(snapshot), ct);

    /// <summary>The signed-in account's email address, shown in Settings.</summary>
    public async Task<string?> Email(CancellationToken ct = default)
    {
        using var doc = JsonDocument.Parse(await Send(HttpMethod.Get, $"{Api}/about?fields=user(emailAddress)", null, ct));
        return doc.RootElement.TryGetProperty("user", out var u) && u.TryGetProperty("emailAddress", out var e) ? e.GetString() : null;
    }

    static ByteArrayContent Json(SyncSnapshot s)
    {
        var content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(s, BriefStore.Json));
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        return content;
    }

    async Task<string> Send(HttpMethod method, string url, HttpContent? content, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(method, url) { Content = content };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await accessToken(ct));
        using var res = await Client.SendAsync(req, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (res.StatusCode == HttpStatusCode.Unauthorized) throw new DriveAuthException("Google sign-in expired");
        if (!res.IsSuccessStatusCode) throw new FetchError($"Google Drive returned HTTP {(int)res.StatusCode}");
        return body;
    }
}
