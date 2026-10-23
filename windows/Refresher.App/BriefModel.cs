using System.Collections.ObjectModel;
using System.Globalization;
using Avalonia.Threading;
using Refresher.Core;

namespace Refresher.App;

/// <summary>One row of the day list.</summary>
public sealed class BriefRow(int rank, BriefItem item, bool isSaved)
{
    public int Rank { get; } = rank;
    public BriefItem Item { get; } = item;
    public bool IsSaved { get; } = isSaved;
    public bool IsTop5 => Rank <= 5;
    public string FieldLabel => Item.Field.Label();
    public string Meta => $"{Item.Source} · {Item.Metric}";
    public bool HasSummary => Item.Summary.Length > 0;
    public bool HasDiscussion => Item.DiscussionURL != null;
    public string SaveTip => IsSaved ? "In your collection" : "Save to collection (or drag it right)";
}

/// <summary>One row of the collection list.</summary>
public sealed class SavedRow(SavedItem saved)
{
    public SavedItem Saved { get; } = saved;
    public string Id => Saved.Id;
    public string Title => Saved.Item.Title;
    public bool IsRead => Saved.IsRead;
    public string Meta => $"{Saved.Item.Field.Label()} · {Saved.Item.Source} · saved {Saved.SavedAt.ToLocalTime():d MMM yyyy}";
    public IReadOnlyList<string> Tags => Saved.Tags;
    public bool HasTags => Saved.Tags.Count > 0;
    public string Note => Saved.Note.ReplaceLineEndings(" ");
    public bool HasNote => Saved.Note.Length > 0;
    public string ReadTip => IsRead ? "Mark as unread" : "Mark as read";
}

public sealed class BriefModel : Observable
{
    /// <summary>%APPDATA%\Refresher on Windows. A preview run on a Mac gets its own folder, since .NET's
    /// ApplicationData there is the macOS app's Application Support folder.</summary>
    public BriefStore Store { get; } = new(OperatingSystem.IsWindows() ? null
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Refresher (Windows preview)"));
    public AppSettings Settings { get; }
    public Notifier Notifier { get; }

    /// <summary>Raised after a new brief was built, for the tray menu.</summary>
    public event Action? BriefChanged;

    public BriefModel()
    {
        Settings = AppSettings.Load(Store);
        Notifier = new Notifier(this);
        ReloadDays();
        SelectedDay = Days.FirstOrDefault();
        collection = Store.LoadCollection();
        RebuildCollection();
        // Checks every 15 minutes, and when the window is activated. Cheap, and survives sleep through noon.
        new DispatcherTimer(TimeSpan.FromMinutes(15), DispatcherPriority.Background, async (_, _) => await RefreshIfDue()).Start();
    }

    // MARK: Daily refresh

    bool isRefreshing;
    public bool IsRefreshing { get => isRefreshing; private set { if (Set(ref isRefreshing, value)) Raise(nameof(EmptyTitle)); } }

    string? lastError;
    public string? LastError { get => lastError; private set { if (Set(ref lastError, value)) Raise(nameof(EmptyMessage)); } }

    public async Task RefreshIfDue()
    {
        if (Schedule.IsDue(DateTimeOffset.Now, Days.FirstOrDefault())) await Refresh(scheduled: true);
    }

    public async Task Refresh(bool scheduled = false)
    {
        if (IsRefreshing) return;
        IsRefreshing = true;
        try
        {
            var store = Store;
            var brief = await Task.Run(() => new BriefBuilder().Run(store));
            LastError = brief.Items.Count == 0 ? "No items fetched — check your connection." : null;
            ReloadDays();
            SelectedDay = brief.Day;
            LoadSelectedBrief();
            BriefChanged?.Invoke();
            if (scheduled && brief.Items.Count > 0) Notifier.BriefReady();
        }
        catch (Exception e) { LastError = e.Message; }
        finally { IsRefreshing = false; }
    }

    // MARK: Day navigation

    public List<string> Days { get; private set; } = [];

    void ReloadDays()
    {
        Days = Store.AvailableDays();
        Raise(nameof(Days), nameof(CanStepOlder), nameof(CanStepNewer));
    }

    string? selectedDay;
    public string? SelectedDay
    {
        get => selectedDay;
        set { if (Set(ref selectedDay, value)) LoadSelectedBrief(); }
    }

    DailyBrief? brief;
    public DailyBrief? Brief => brief;
    /// <summary>The newest brief, for the tray menu.</summary>
    public DailyBrief? Latest => Days.Count > 0 ? (Days[0] == SelectedDay ? brief : Store.Brief(Days[0])) : null;

    public ObservableCollection<BriefRow> Rows { get; } = [];

    void LoadSelectedBrief()
    {
        brief = SelectedDay is { } d ? Store.Brief(d) : null;
        RebuildRows();
        Raise(nameof(Brief), nameof(DayTitle), nameof(DaySubtitle), nameof(HasErrors), nameof(ErrorsTip),
              nameof(CanStepOlder), nameof(CanStepNewer));
    }

    void RebuildRows()
    {
        var saved = SavedIDs;
        Rows.Clear();
        var items = brief?.Items ?? [];
        for (var i = 0; i < items.Count; i++) Rows.Add(new BriefRow(i + 1, items[i], saved.Contains(items[i].Id)));
        Raise(nameof(HasItems));
    }

    public bool HasItems => Rows.Count > 0;
    public string EmptyTitle => IsRefreshing ? "Fetching today's brief…" : "No brief yet";
    public string EmptyMessage => LastError ?? "A new brief is built every day after 12:00.";

    public string DayTitle
    {
        get
        {
            if (SelectedDay is not { } day || day == Day.String(DateTimeOffset.Now)) return "Today";
            return DateTime.TryParseExact(day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
                ? d.ToString("dddd, d MMM", CultureInfo.CurrentCulture) : day;
        }
    }

    public string DaySubtitle => brief is { } b ? $"{b.Items.Count} items · built {b.GeneratedAt.ToLocalTime():t}" : "";
    public bool HasErrors => brief?.Errors.Count > 0;
    public string ErrorsTip => brief is { Errors.Count: > 0 } b ? "Some sources failed:\n" + string.Join("\n", b.Errors) : "";

    int SelectedIndex => SelectedDay is { } d ? Days.IndexOf(d) : -1;
    // Days are stored newest first.
    public bool CanStepOlder => SelectedIndex >= 0 && SelectedIndex + 1 < Days.Count;
    public bool CanStepNewer => SelectedIndex > 0;
    public void StepOlder() { if (CanStepOlder) SelectedDay = Days[SelectedIndex + 1]; }
    public void StepNewer() { if (CanStepNewer) SelectedDay = Days[SelectedIndex - 1]; }

    // MARK: Collection

    List<SavedItem> collection = [];
    public IReadOnlyList<SavedItem> Collection => collection;
    public HashSet<string> SavedIDs => collection.Select(s => s.Id).ToHashSet();
    public int CollectionCount => collection.Count;
    public bool CollectionIsEmpty => collection.Count == 0;

    public ObservableCollection<SavedRow> FilteredCollection { get; } = [];
    public ObservableCollection<string> TagChoices { get; } = [AllTags];
    public const string AllTags = "All tags";

    string search = "";
    public string Search { get => search; set { if (Set(ref search, value)) RebuildCollection(); } }

    /// <summary>0 = all, 1 = unread, 2 = read.</summary>
    int readFilter;
    public int ReadFilter { get => readFilter; set { if (Set(ref readFilter, value)) RebuildCollection(); } }

    string tagFilter = AllTags;
    public string TagFilter
    {
        get => tagFilter;
        set { if (Set(ref tagFilter, value ?? AllTags)) RebuildCollection(); }
    }

    SavedRow? selected;
    public SavedRow? Selected
    {
        get => selected;
        set
        {
            var changedItem = value?.Id != selected?.Id;
            if (changedItem)
            {
                CommitTags();
                // Committing can rebuild the list; point at the current copy of the row.
                if (value != null) value = FilteredCollection.FirstOrDefault(r => r.Id == value.Id) ?? value;
            }
            if (!Set(ref selected, value)) return;
            Raise(nameof(HasSelection));
            if (!changedItem) return;
            // A different item: load its tags and note into the editor.
            tagsText = string.Join(", ", value?.Saved.Tags ?? []);
            note = value?.Saved.Note ?? "";
            Raise(nameof(TagsText), nameof(Note));
        }
    }
    public bool HasSelection => selected != null;

    string tagsText = "";
    public string TagsText { get => tagsText; set => Set(ref tagsText, value); }

    string note = "";
    public string Note
    {
        get => note;
        set
        {
            if (!Set(ref note, value) || selected is not { } row) return;
            Update(row.Id, s => s with { Note = value }, rebuild: false);
        }
    }

    /// <summary>Applies the tags field (comma separated, lowercased, no duplicates).</summary>
    public void CommitTags()
    {
        if (selected is not { } row) return;
        var tags = tagsText.Split(',').Select(t => t.Trim().ToLowerInvariant()).Where(t => t.Length > 0).Distinct().ToList();
        if (tags.SequenceEqual(row.Saved.Tags)) return;
        Update(row.Id, s => s with { Tags = tags });
    }

    public void ReloadCollection()
    {
        collection = Store.LoadCollection();
        CollectionChanged();
    }

    public void Save(BriefItem item) => Mutate(items =>
    {
        if (!items.Any(s => s.Id == item.Id)) items.Insert(0, new SavedItem { Item = item });
    });

    public void Remove(string id) => Mutate(items => items.RemoveAll(s => s.Id == id));

    public void ToggleRead(string id) => Update(id, s => s with { IsRead = !s.IsRead });

    public void Select(string id) => Selected = FilteredCollection.FirstOrDefault(r => r.Id == id);

    void Update(string id, Func<SavedItem, SavedItem> change, bool rebuild = true)
    {
        Mutate(items =>
        {
            var i = items.FindIndex(s => s.Id == id);
            if (i >= 0) items[i] = change(items[i]);
        }, rebuild);
    }

    void Mutate(Action<List<SavedItem>> change, bool rebuild = true)
    {
        try { collection = Store.UpdateCollection(change); }
        catch (Exception e) { LastError = $"Could not save collection: {e.Message}"; return; }
        if (rebuild) CollectionChanged();
        else if (selected is { } row && collection.FirstOrDefault(s => s.Id == row.Id) is { } updated)
        {
            // Typing a note: refresh that row's preview without rebuilding the list (keeps focus and selection).
            var i = FilteredCollection.IndexOf(row);
            selected = new SavedRow(updated);
            if (i >= 0) FilteredCollection[i] = selected;
            Raise(nameof(Selected));
        }
    }

    void CollectionChanged()
    {
        RebuildCollection();
        RebuildRows(); // bookmark state on the left
        BriefChanged?.Invoke();
    }

    void RebuildCollection()
    {
        var tags = collection.SelectMany(s => s.Tags).Distinct().Order(StringComparer.Ordinal).ToList();
        if (!TagChoices.Skip(1).SequenceEqual(tags))
        {
            var keep = tagFilter;
            while (TagChoices.Count > 1) TagChoices.RemoveAt(1);
            foreach (var t in tags) TagChoices.Add(t);
            tagFilter = TagChoices.Contains(keep) ? keep : AllTags;
            Raise(nameof(TagFilter));
        }

        var keepID = selected?.Id;
        var filtered = collection.Where(s =>
            (tagFilter == AllTags || s.Tags.Contains(tagFilter))
            && (readFilter == 0 || s.IsRead == (readFilter == 2))
            && (search.Length == 0 || new[] { s.Item.Title, s.Item.Summary, s.Note, string.Join(" ", s.Tags) }
                .Any(t => t.Contains(search, StringComparison.CurrentCultureIgnoreCase))));
        FilteredCollection.Clear();
        foreach (var s in filtered) FilteredCollection.Add(new SavedRow(s));
        // Keep the editor on the same item without reloading its fields.
        selected = FilteredCollection.FirstOrDefault(r => r.Id == keepID);
        Raise(nameof(Selected), nameof(HasSelection), nameof(CollectionCount), nameof(CollectionIsEmpty));
    }
}
