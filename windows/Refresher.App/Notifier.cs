#if WINDOWS
using Microsoft.Toolkit.Uwp.Notifications;
using Windows.UI.Notifications;
#endif
using Avalonia.Threading;

namespace Refresher.App;

/// <summary>
/// The daily "new brief" notification: opt-in from the bell button. Sent when the app (running in
/// the notification area) builds the day's brief after 12:00. Clicking it opens the window.
/// </summary>
public sealed class Notifier : Observable
{
    public enum State { Off, On, BlockedInWindowsSettings, Unavailable }

    readonly BriefModel model;

    public Notifier(BriefModel model)
    {
        this.model = model;
#if WINDOWS
        ToastNotificationManagerCompat.OnActivated += _ => Dispatcher.UIThread.Post(() => App.Current?.ShowMainWindow());
#endif
        RefreshState();
    }

    State state;
    public State Current { get => state; private set { if (Set(ref state, value)) Raise(nameof(IsOn), nameof(IsAvailable), nameof(Tip), nameof(ActionLabel)); } }
    public bool IsOn => state == State.On;
    public bool IsAvailable => state != State.Unavailable;

    public string Tip => state switch
    {
        State.On => "Notifying you when the daily brief is ready. Click to turn off.",
        State.Off => "Get a notification when the daily brief is ready.",
        State.BlockedInWindowsSettings => $"Notifications are blocked for {AppBrand.DisplayName}. Click to open Windows Settings.",
        _ => "",
    };

    public string ActionLabel => state switch
    {
        State.On => "Turn Off",
        State.Off => "Turn On",
        State.BlockedInWindowsSettings => "Open Windows Settings…",
        _ => "",
    };

    /// <summary>Re-reads the system setting, which can change in Windows Settings at any time.</summary>
    public void RefreshState()
    {
#if WINDOWS
        var blocked = false;
        try { blocked = ToastNotificationManagerCompat.CreateToastNotifier().Setting != NotificationSetting.Enabled; }
        catch (Exception) { /* No notification platform (e.g. Windows Server Core): treat as allowed. */ }
        Current = !model.Settings.Notifications ? State.Off : blocked ? State.BlockedInWindowsSettings : State.On;
#else
        Current = State.Unavailable;
#endif
    }

    /// <summary>The bell button.</summary>
    public void Toggle()
    {
        switch (state)
        {
            case State.On or State.Off:
                model.Settings.Notifications = state == State.Off;
                model.Settings.Save(model.Store);
                break;
            case State.BlockedInWindowsSettings:
                Shell.Open("ms-settings:notifications");
                break;
        }
        RefreshState();
    }

    public void BriefReady()
    {
        RefreshState();
        if (state == State.On) Show();
    }

    public void SendTest()
    {
        if (state == State.On) Show();
    }

    void Show()
    {
#if WINDOWS
        new ToastContentBuilder()
            .AddText("Most recent AI & ML trends for you")
            .AddText($"Today's top picks are ready in {AppBrand.DisplayName}.")
            .Show();
#endif
    }
}
