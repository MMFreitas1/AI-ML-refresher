using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using Refresher.App.Views;
using Refresher.Core;

namespace Refresher.App;

/// <summary>
/// Lives in the notification area: it starts with Windows (hidden), builds the brief after 12:00,
/// and its menu lists today's top 5. Closing the window keeps it running there; Quit ends it.
/// </summary>
public partial class App : Application
{
    public static new App? Current => Application.Current as App;

    BriefModel? model;
    MainWindow? window;
    TrayIcon? tray;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is not IClassicDesktopStyleApplicationLifetime desktop) return;
        AppBrand.Prepare(this);
        Name = AppBrand.DisplayName;
        model = new BriefModel();
        model.BriefChanged += RebuildTrayMenu;

        try { Startup.Apply(model.Settings.StartWithWindows); }
        catch (Exception e) { System.Diagnostics.Trace.WriteLine($"startup entry: {e.Message}"); }

        tray = new TrayIcon { Icon = AppBrand.Icon(), ToolTipText = AppBrand.DisplayName, Menu = [] };
        tray.Clicked += (_, _) => ShowMainWindow();
        TrayIcon.SetIcons(this, [tray]);
        RebuildTrayMenu();

        Program.ListenForOtherInstances(() => Dispatcher.UIThread.Post(ShowMainWindow));

        // Started with Windows: stay in the notification area until asked.
        if (!(desktop.Args ?? []).Contains(Startup.BackgroundArg)) ShowMainWindow();
        Dispatcher.UIThread.Post(async () => await model.RefreshIfDue(), DispatcherPriority.Background);
        base.OnFrameworkInitializationCompleted();
    }

    public void ShowMainWindow()
    {
        if (model == null) return;
        window ??= new MainWindow(model);
        window.Present();
    }

    public void Quit()
    {
        window?.AllowClose();
        (ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.Shutdown();
    }

    /// <summary>The notification-area menu: today's top 5 (open, save), then the app's commands.</summary>
    void RebuildTrayMenu()
    {
        if (tray == null || model == null) return;
        // Rebuilt in place: some platforms don't allow replacing a tray icon's menu.
        var menu = tray.Menu!;
        menu.Items.Clear();
        var latest = model.Latest;
        var isToday = latest?.Day == Day.String(DateTimeOffset.Now);
        menu.Add(new NativeMenuItem(latest == null ? "No brief yet" : isToday ? "Top 5 today" : $"Top 5 · {latest.Day}") { IsEnabled = false });

        var saved = model.SavedIDs;
        foreach (var (item, i) in (latest?.Items ?? []).Take(5).Select((item, i) => (item, i)))
        {
            var title = item.Title.Length > 60 ? item.Title[..59].TrimEnd() + "…" : item.Title;
            var entry = new NativeMenuItem($"{i + 1}. {title}") { Menu = [] };
            entry.Menu.Add(Command("Open Link", () => Shell.Open(item.Url)));
            if (item.DiscussionURL is { } discussion) entry.Menu.Add(Command("Open Discussion", () => Shell.Open(discussion)));
            entry.Menu.Add(saved.Contains(item.Id)
                ? new NativeMenuItem("In your collection") { IsEnabled = false }
                : Command("Save to Collection", () => model.Save(item)));
            menu.Add(entry);
        }

        menu.Add(new NativeMenuItemSeparator());
        menu.Add(Command($"Open {AppBrand.DisplayName}", ShowMainWindow));
        menu.Add(Command("Rebuild Today's Brief", async () => await model.Refresh()));
        menu.Add(Command("Settings…", () => { ShowMainWindow(); window?.OpenSettings(); }));
        menu.Add(new NativeMenuItemSeparator());
        menu.Add(Command("Quit", Quit));
    }

    static NativeMenuItem Command(string header, Action action)
    {
        var item = new NativeMenuItem(header);
        item.Click += (_, _) => action();
        return item;
    }
}
