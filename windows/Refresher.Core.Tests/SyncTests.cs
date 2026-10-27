using Refresher.Core;

namespace Refresher.Core.Tests;

static class S
{
    public static DateTimeOffset At(int minute) => new DateTimeOffset(2026, 10, 27, 12, 0, 0, TimeSpan.Zero).AddMinutes(minute);

    public static SavedItem Saved(string id, int savedMin, int? updatedMin = null, string note = "") => new()
    {
        Item = new BriefItem($"https://example.com/{id}", id, "", SourceKind.blog, "Blog", "", 1),
        SavedAt = At(savedMin), Note = note, UpdatedAt = updatedMin is { } u ? At(u) : null,
    };

    public static SyncSnapshot Snap(params SavedItem[] items) => new([.. items], []);
}

public class MergeTests
{
    [Fact]
    public void NewestCopyWins()
    {
        var local = S.Snap(S.Saved("a", 0, 5, "local"));
        var remote = S.Snap(S.Saved("a", 0, 7, "remote"));
        Assert.Equal("remote", CollectionSync.Merge(local, remote).Items.Single().Note);
        Assert.Equal("remote", CollectionSync.Merge(remote, local).Items.Single().Note);
    }

    [Fact]
    public void RemovalBeatsOlderCopiesButNotNewerOnes()
    {
        var removedAt3 = new SyncSnapshot([], new() { ["example.com/a"] = S.At(3) });
        Assert.Empty(CollectionSync.Merge(S.Snap(S.Saved("a", 0, 2)), removedAt3).Items);
        var kept = CollectionSync.Merge(S.Snap(S.Saved("a", 0, 4)), removedAt3);
        Assert.Single(kept.Items);
        Assert.Empty(kept.Deleted);
    }

    [Fact]
    public void SymmetricAndIdempotent()
    {
        var a = new SyncSnapshot([S.Saved("a", 0, 1), S.Saved("b", 1, 6)], new() { ["example.com/c"] = S.At(4) });
        var b = S.Snap(S.Saved("b", 1, 3), S.Saved("c", 2, 2), S.Saved("d", 3));
        var ab = CollectionSync.Merge(a, b);
        Assert.True(ab.SameAs(CollectionSync.Merge(b, a)));
        Assert.True(ab.SameAs(CollectionSync.Merge(ab, ab)));
        Assert.Equal(["example.com/d", "example.com/b", "example.com/a"], ab.Items.Select(i => i.Id));
    }

    /// The sync file is shared with the Android and macOS apps.
    [Fact]
    public void ReadsTheSharedSyncFormat()
    {
        const string json = """
            {"items":[{"item":{"id":"x","title":"T","summary":"","url":"https://x","kind":"blog","source":"B","metric":"",
              "rawScore":1.0,"score":0.0,"field":"Agents"},"savedAt":"2026-10-21T18:02:11Z","tags":["t"],"note":"",
              "isRead":true,"updatedAt":"2026-10-22T08:00:00Z"}],"deleted":{"example.com/gone":"2026-10-23T09:30:00Z"}}
            """;
        var s = System.Text.Json.JsonSerializer.Deserialize<SyncSnapshot>(json, BriefStore.Json)!;
        Assert.Equal(new DateTimeOffset(2026, 10, 22, 8, 0, 0, TimeSpan.Zero), s.Items[0].UpdatedAt);
        Assert.Equal(new DateTimeOffset(2026, 10, 23, 9, 30, 0, TimeSpan.Zero), s.Deleted["example.com/gone"]);
        var back = System.Text.Json.JsonSerializer.Serialize(s, BriefStore.Json);
        Assert.Contains("\"example.com/gone\": \"2026-10-23T09:30:00Z\"", back);
        Assert.Contains("\"updatedAt\": \"2026-10-22T08:00:00Z\"", back);
    }
}

public class SyncerTests : IDisposable
{
    sealed class FakeRemote : IRemoteCollection
    {
        public SyncSnapshot? File;
        public int Writes;
        public Task<string?> Find(CancellationToken ct = default) => Task.FromResult(File is null ? null : "id");
        public Task<SyncSnapshot> Read(string id, CancellationToken ct = default) => Task.FromResult(File!);
        public Task<string> Create(SyncSnapshot s, CancellationToken ct = default) { File = s; Writes++; return Task.FromResult("id"); }
        public Task Update(string id, SyncSnapshot s, CancellationToken ct = default) { File = s; Writes++; return Task.CompletedTask; }
    }

    readonly string[] dirs = [Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()), Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString())];
    public void Dispose() { foreach (var d in dirs) if (Directory.Exists(d)) Directory.Delete(d, true); }

    [Fact]
    public void EditsAreStampedAndRemovalsRecorded()
    {
        var store = new BriefStore(dirs[0]);
        store.UpdateCollection(i => { i.Add(S.Saved("a", 0)); i.Add(S.Saved("b", 0)); }, S.At(0));
        store.UpdateCollection(i => i[0] = i[0] with { Tags = ["x"] }, S.At(5));
        var items = store.LoadCollection();
        Assert.Equal(S.At(5), items[0].UpdatedAt);
        Assert.Equal(S.At(0), items[1].UpdatedAt);
        store.UpdateCollection(i => i.RemoveAll(s => s.Id == "example.com/b"), S.At(9));
        Assert.Equal(S.At(9), store.LoadDeleted()["example.com/b"]);
    }

    [Fact]
    public async Task TwoDevicesConverge()
    {
        var remote = new FakeRemote();
        var phone = new BriefStore(dirs[0]);
        var pc = new BriefStore(dirs[1]);
        phone.UpdateCollection(i => i.Add(S.Saved("a", 1)), S.At(1));
        pc.UpdateCollection(i => i.Add(S.Saved("b", 2)), S.At(2));

        await new CollectionSyncer(phone, remote).Sync();
        Assert.True((await new CollectionSyncer(pc, remote).Sync()).ChangedLocally);
        await new CollectionSyncer(phone, remote).Sync();
        Assert.Equal(2, phone.LoadCollection().Count);
        Assert.Equal(phone.LoadCollection().Select(BriefStore.Fingerprint), pc.LoadCollection().Select(BriefStore.Fingerprint));

        pc.UpdateCollection(i => i.RemoveAll(s => s.Id == "example.com/a"), S.At(3));
        await new CollectionSyncer(pc, remote).Sync();
        await new CollectionSyncer(phone, remote).Sync();
        Assert.Equal(["example.com/b"], phone.LoadCollection().Select(s => s.Id));

        var writes = remote.Writes;
        Assert.False((await new CollectionSyncer(phone, remote).Sync()).Uploaded);
        Assert.Equal(writes, remote.Writes);
    }
}
