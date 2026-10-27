using Avalonia.Controls;
using Avalonia.Interactivity;
using Refresher.Core;

namespace Refresher.App.Views;

public partial class SettingsWindow : Window
{
    readonly BriefModel model;
    readonly bool loading = true;

    public SettingsWindow() : this(new BriefModel()) { } // XAML previewer

    public SettingsWindow(BriefModel model)
    {
        this.model = model;
        DataContext = model;
        InitializeComponent();
        Title = $"{AppBrand.DisplayName} Settings";
        Icon = AppBrand.Icon();

        StartWithWindows.IsChecked = model.Settings.StartWithWindows;
        StartWithWindows.IsEnabled = Startup.IsAvailable;
        StartHelp.Text = $"Runs {AppBrand.DisplayName} in the notification area, where it builds the brief after 12:00 "
                         + "and lists the top 5, even with this window closed.";
        AppearanceSection.IsVisible = AppBrand.HasIntro;
        SyncSection.IsVisible = model.Sync.IsAvailable;
        PlayIntro.IsChecked = model.Settings.PlayIntro;
        ScheduleText.Text = $"Daily after {Schedule.RefreshHour}:00 local time";
        NextText.Text = Schedule.NextRefresh(DateTimeOffset.Now).ToLocalTime().ToString("g");
        model.Notifier.RefreshState();
        loading = false;
    }

    void OnStartWithWindows(object? sender, RoutedEventArgs e)
    {
        if (loading) return;
        var on = StartWithWindows.IsChecked == true;
        model.Settings.StartWithWindows = on;
        model.Settings.Save(model.Store);
        try { Startup.Apply(on); StartError.IsVisible = false; }
        catch (Exception ex) { StartError.Text = ex.Message; StartError.IsVisible = true; }
    }

    void OnPlayIntro(object? sender, RoutedEventArgs e)
    {
        if (loading) return;
        model.Settings.PlayIntro = PlayIntro.IsChecked == true;
        model.Settings.Save(model.Store);
    }

    void OnToggleNotifications(object? sender, RoutedEventArgs e) => model.Notifier.Toggle();
    void OnTestNotification(object? sender, RoutedEventArgs e) => model.Notifier.SendTest();
    void OnOpenFolder(object? sender, RoutedEventArgs e) => Shell.Open(model.Store.Directory);
    async void OnSignIn(object? sender, RoutedEventArgs e) => await model.Sync.SignIn();
    void OnCancelSignIn(object? sender, RoutedEventArgs e) => model.Sync.CancelSignIn();
    async void OnSyncNow(object? sender, RoutedEventArgs e) => await model.Sync.Sync();
    void OnSignOut(object? sender, RoutedEventArgs e) => model.Sync.SignOut();
}
