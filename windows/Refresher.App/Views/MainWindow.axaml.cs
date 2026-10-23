using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Threading;
using Refresher.Core;

namespace Refresher.App.Views;

/// <summary>The two-pane window: the day's items on the left, the collection on the right.</summary>
public partial class MainWindow : Window
{
    /// <summary>Items are dragged as objects; the format only exists inside this app.</summary>
    static readonly DataFormat<BriefItem> ItemFormat = DataFormat.CreateInProcessFormat<BriefItem>("refresher-item");

    readonly BriefModel model;
    bool allowClose;
    bool hasShown;
    SettingsWindow? settings;

    public MainWindow() : this(new BriefModel()) { } // XAML previewer

    public MainWindow(BriefModel model)
    {
        this.model = model;
        DataContext = model;
        InitializeComponent();
        Title = AppBrand.DisplayName;
        Icon = AppBrand.Icon();

        CollectionPane.AddHandler(DragDrop.DragEnterEvent, OnDragOver);
        CollectionPane.AddHandler(DragDrop.DragOverEvent, OnDragOver);
        CollectionPane.AddHandler(DragDrop.DragLeaveEvent, (_, _) => DropHighlight.IsVisible = false);
        CollectionPane.AddHandler(DragDrop.DropEvent, OnDrop);

        Activated += async (_, _) =>
        {
            // The tray menu's save writes to the same file.
            model.ReloadCollection();
            model.Notifier.RefreshState();
            await model.RefreshIfDue();
        };
    }

    /// <summary>Shows and focuses the window. The intro plays the first time in each run.</summary>
    public void Present()
    {
        if (!hasShown)
        {
            hasShown = true;
            if (AppBrand.HasIntro && model.Settings.PlayIntro) PlayIntro();
        }
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    /// <summary>Closing hides the window; the app keeps running in the notification area.</summary>
    protected override void OnClosing(WindowClosingEventArgs e)
    {
        model.CommitTags();
        if (!allowClose)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }

    public void AllowClose() => allowClose = true;


    void PlayIntro()
    {
        var intro = AppBrand.Intro(() => !model.IsRefreshing, () =>
        {
            IntroHost.Opacity = 0;
            DispatcherTimer.RunOnce(() => { IntroHost.IsVisible = false; IntroHost.Content = null; }, TimeSpan.FromMilliseconds(450));
        });
        if (intro == null) return;
        IntroHost.Content = intro;
        IntroHost.Opacity = 1;
        IntroHost.IsVisible = true;
    }

    public void OpenSettings()
    {
        if (settings is { IsVisible: true }) { settings.Activate(); return; }
        settings = new SettingsWindow(model);
        settings.Show(this);
    }

    // MARK: Header

    void OnOlder(object? sender, RoutedEventArgs e) => model.StepOlder();
    void OnNewer(object? sender, RoutedEventArgs e) => model.StepNewer();
    async void OnRefresh(object? sender, RoutedEventArgs e) => await model.Refresh();
    void OnBell(object? sender, RoutedEventArgs e) => model.Notifier.Toggle();
    void OnSettings(object? sender, RoutedEventArgs e) => OpenSettings();

    // MARK: Item actions (day rows and collection rows share these)

    static BriefItem? ItemOf(object? sender) => (sender as StyledElement)?.DataContext switch
    {
        BriefRow row => row.Item,
        SavedRow saved => saved.Saved.Item,
        _ => null,
    };

    void OnOpenLink(object? sender, RoutedEventArgs e) { if (ItemOf(sender) is { } item) Shell.Open(item.Url); }

    void OnOpenDiscussion(object? sender, RoutedEventArgs e)
    {
        if (ItemOf(sender)?.DiscussionURL is { } url) Shell.Open(url);
    }

    async void OnCopyLink(object? sender, RoutedEventArgs e)
    {
        if (ItemOf(sender) is { } item && Clipboard is { } clipboard) await clipboard.SetTextAsync(item.Url);
    }

    void OnSaveRow(object? sender, RoutedEventArgs e) { if (ItemOf(sender) is { } item) model.Save(item); }

    void OnRowDoubleTapped(object? sender, TappedEventArgs e) { if (ItemOf(sender) is { } item) Shell.Open(item.Url); }

    void OnSavedDoubleTapped(object? sender, TappedEventArgs e) { if (ItemOf(sender) is { } item) Shell.Open(item.Url); }

    void OnToggleRead(object? sender, RoutedEventArgs e)
    {
        if ((sender as StyledElement)?.DataContext is SavedRow row) model.ToggleRead(row.Id);
    }

    void OnRemove(object? sender, RoutedEventArgs e)
    {
        if ((sender as StyledElement)?.DataContext is SavedRow row) model.Remove(row.Id);
    }

    void OnSavedKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key is Key.Delete or Key.Back && model.Selected is { } row && e.Source is not TextBox)
        {
            model.Remove(row.Id);
            e.Handled = true;
        }
    }

    void OnOpenSelected(object? sender, RoutedEventArgs e) { if (model.Selected is { } row) Shell.Open(row.Saved.Item.Url); }

    void OnOpenSelectedDiscussion(object? sender, RoutedEventArgs e)
    {
        if (model.Selected?.Saved.Item.DiscussionURL is { } url) Shell.Open(url);
    }

    void OnTagsKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { model.CommitTags(); e.Handled = true; }
    }

    void OnTagsLostFocus(object? sender, RoutedEventArgs e) => model.CommitTags();

    // MARK: Drag from the day list to the collection

    Point? pressedAt;
    PointerPressedEventArgs? pressEvent;

    void OnRowPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
        pressedAt = e.GetPosition(this);
        pressEvent = e;
    }

    async void OnRowMoved(object? sender, PointerEventArgs e)
    {
        if (pressedAt is not { } start || pressEvent is not { } press || ItemOf(sender) is not { } item) return;
        if (!e.GetCurrentPoint(this).Properties.IsLeftButtonPressed) { pressedAt = null; return; }
        var d = e.GetPosition(this) - start;
        if (Math.Abs(d.X) < 6 && Math.Abs(d.Y) < 6) return;
        pressedAt = null;
        var data = new DataTransfer();
        data.Add(DataTransferItem.Create(ItemFormat, item));
        // Other apps (browser, notes) get the link.
        data.Add(DataTransferItem.CreateText(item.Url));
        await DragDrop.DoDragDropAsync(press, data, DragDropEffects.Copy);
    }

    void OnDragOver(object? sender, DragEventArgs e)
    {
        var accepts = e.DataTransfer.Contains(ItemFormat);
        e.DragEffects = accepts ? DragDropEffects.Copy : DragDropEffects.None;
        DropHighlight.IsVisible = accepts;
    }

    void OnDrop(object? sender, DragEventArgs e)
    {
        DropHighlight.IsVisible = false;
        var items = e.DataTransfer.TryGetValues(ItemFormat) ?? [];
        foreach (var item in items) model.Save(item);
        if (items.FirstOrDefault() is { } first) model.Select(first.Id);
    }
}
