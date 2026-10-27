using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Refresher.Core;

/// <summary>
/// Plain JSON files on disk, in the same format as the macOS app (so the files can move between them):
///
///     &lt;dir&gt;/briefs/2026-10-08.json   one ranked list per day (kept as history)
///     &lt;dir&gt;/collection.json          saved items with tags, notes and read state
///     &lt;dir&gt;/deleted.json             when each removed item was removed, so removals sync
///
/// &lt;dir&gt; defaults to %APPDATA%\Refresher on Windows.
/// </summary>
public sealed class BriefStore
{
    public string Directory { get; }
    readonly object _lock = new();

    public static string DefaultDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Refresher");

    public BriefStore(string? directory = null)
    {
        Directory = directory ?? DefaultDirectory;
        System.IO.Directory.CreateDirectory(BriefsDirectory);
    }

    string BriefsDirectory => Path.Combine(Directory, "briefs");
    string CollectionPath => Path.Combine(Directory, "collection.json");
    string DeletedPath => Path.Combine(Directory, "deleted.json");

    public static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        // Keep "&", "★" and the like readable, as Swift writes them.
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new SwiftDateConverter() },
    };

    // MARK: Briefs

    public void Save(DailyBrief brief) =>
        WriteAtomic(Path.Combine(BriefsDirectory, $"{brief.Day}.json"), JsonSerializer.SerializeToUtf8Bytes(brief, Json));

    public DailyBrief? Brief(string day)
    {
        try { return JsonSerializer.Deserialize<DailyBrief>(File.ReadAllBytes(Path.Combine(BriefsDirectory, $"{day}.json")), Json); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>Days with a saved brief, newest first.</summary>
    public List<string> AvailableDays() =>
        System.IO.Directory.EnumerateFiles(BriefsDirectory, "*.json")
            .Select(Path.GetFileNameWithoutExtension).OfType<string>()
            .OrderDescending(StringComparer.Ordinal).ToList();

    public DailyBrief? LatestBrief() => AvailableDays().Select(Brief).FirstOrDefault(b => b != null);

    /// <summary>Item IDs shown in the <paramref name="days"/> briefs before <paramref name="before"/>,
    /// so the same repo isn't served again tomorrow.</summary>
    public HashSet<string> SeenIDs(string before, int days = 7) =>
        AvailableDays().Where(d => string.CompareOrdinal(d, before) < 0).Take(days)
            .Select(Brief).OfType<DailyBrief>().SelectMany(b => b.Items.Select(i => i.Id)).ToHashSet();

    // MARK: Collection

    public List<SavedItem> LoadCollection()
    {
        lock (_lock) return ReadCollection();
    }

    /// <summary>Read-modify-write under a lock, so the tray menu and the window don't overwrite each other.
    /// Changed items get a new UpdatedAt and removed ones a deletion time, for syncing.</summary>
    public List<SavedItem> UpdateCollection(Action<List<SavedItem>> mutate, DateTimeOffset? now = null)
    {
        lock (_lock)
        {
            var at = now ?? SyncClock.Now;
            var before = ReadCollection().ToDictionary(s => s.Id, Fingerprint);
            var items = ReadCollection();
            mutate(items);
            for (var i = 0; i < items.Count; i++)
                if (!before.TryGetValue(items[i].Id, out var old) || old != Fingerprint(items[i]))
                    items[i] = items[i] with { UpdatedAt = at };

            var deleted = ReadDeleted();
            var kept = items.Select(s => s.Id).ToHashSet();
            var removed = before.Keys.Where(id => !kept.Contains(id)).ToList();
            if (removed.Count > 0 || kept.Any(deleted.ContainsKey))
            {
                foreach (var id in removed) deleted[id] = at;
                foreach (var id in kept) deleted.Remove(id);
                WriteAtomic(DeletedPath, JsonSerializer.SerializeToUtf8Bytes(deleted, Json));
            }
            WriteAtomic(CollectionPath, JsonSerializer.SerializeToUtf8Bytes(items, Json));
            return items;
        }
    }

    /// <summary>Removed item IDs and when they were removed.</summary>
    public Dictionary<string, DateTimeOffset> LoadDeleted()
    {
        lock (_lock) return ReadDeleted();
    }

    /// <summary>Applies a sync: merges <paramref name="remote"/> into the collection under the lock, without
    /// re-stamping, and returns the merged state. Local changes made meanwhile are part of the merge.</summary>
    public SyncSnapshot MergeCollection(SyncSnapshot remote)
    {
        lock (_lock)
        {
            var merged = CollectionSync.Merge(new SyncSnapshot(ReadCollection(), ReadDeleted()), remote);
            WriteAtomic(DeletedPath, JsonSerializer.SerializeToUtf8Bytes(merged.Deleted, Json));
            WriteAtomic(CollectionPath, JsonSerializer.SerializeToUtf8Bytes(merged.Items, Json));
            return merged;
        }
    }

    /// <summary>Content comparison (records compare lists by reference).</summary>
    internal static string Fingerprint(SavedItem s) => JsonSerializer.Serialize(s, Json);

    /// <summary>Adds the item if it isn't saved yet. Returns false when it was already there.</summary>
    public bool Save(BriefItem item)
    {
        var added = false;
        UpdateCollection(items =>
        {
            if (items.Any(s => s.Id == item.Id)) return;
            items.Insert(0, new SavedItem { Item = item });
            added = true;
        });
        return added;
    }

    List<SavedItem> ReadCollection()
    {
        try { return JsonSerializer.Deserialize<List<SavedItem>>(File.ReadAllBytes(CollectionPath), Json) ?? []; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return []; }
    }

    Dictionary<string, DateTimeOffset> ReadDeleted()
    {
        try { return JsonSerializer.Deserialize<Dictionary<string, DateTimeOffset>>(File.ReadAllBytes(DeletedPath), Json) ?? []; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return []; }
    }

    static void WriteAtomic(string path, byte[] data)
    {
        var tmp = path + ".tmp";
        File.WriteAllBytes(tmp, data);
        File.Move(tmp, path, overwrite: true);
    }
}

/// <summary>ISO 8601 without fractional seconds, in UTC: what Swift's .iso8601 strategy reads and writes.</summary>
sealed class SwiftDateConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        Iso8601.Parse(reader.GetString()) ?? throw new JsonException("Bad date");

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
}

/// <summary>Fields are stored by their display name, as in the macOS app.</summary>
sealed class FieldConverter : JsonConverter<Field>
{
    public override Field Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        FieldInfo.FromLabel(reader.GetString() ?? "") ?? Field.General;

    public override void Write(Utf8JsonWriter writer, Field value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.Label());
}
