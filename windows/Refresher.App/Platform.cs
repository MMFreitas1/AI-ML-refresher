using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Refresher.Core;

namespace Refresher.App;

public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }

    protected void Raise(params string?[] names)
    {
        foreach (var name in names) PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

/// <summary>Opens links and folders with the system's default handler.</summary>
public static class Shell
{
    public static void Open(string target)
    {
        try
        {
            if (OperatingSystem.IsMacOS()) Process.Start("open", [target]);
            else if (OperatingSystem.IsLinux()) Process.Start("xdg-open", [target]);
            else Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception e) { Trace.WriteLine($"Could not open {target}: {e.Message}"); }
    }
}

/// <summary>App preferences, stored next to the data as settings.json.</summary>
public sealed class AppSettings
{
    public bool StartWithWindows { get; set; } = true;
    public bool Notifications { get; set; }
    public bool PlayIntro { get; set; } = true;

    static string PathIn(BriefStore store) => Path.Combine(store.Directory, "settings.json");

    public static AppSettings Load(BriefStore store)
    {
        try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllBytes(PathIn(store)), BriefStore.Json) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }

    public void Save(BriefStore store)
    {
        try { File.WriteAllBytes(PathIn(store), JsonSerializer.SerializeToUtf8Bytes(this, BriefStore.Json)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Trace.WriteLine($"settings: {e.Message}"); }
    }
}

/// <summary>
/// "Start with Windows": a per-user Run entry that launches the app hidden in the notification
/// area, where it builds the brief after 12:00 even with the window closed.
/// </summary>
public static class Startup
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string ValueName = "AI-ML Refresher";
    public const string BackgroundArg = "--background";

    public static bool IsAvailable => OperatingSystem.IsWindows() && Environment.ProcessPath is not null;

    /// <summary>Registers or removes the entry to match the setting. Re-run at every launch, so the
    /// entry follows the .exe if it's moved or replaced.</summary>
    public static void Apply(bool enabled)
    {
        if (!OperatingSystem.IsWindows() || Environment.ProcessPath is not { } exe) return;
        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey);
        var command = $"\"{exe}\" {BackgroundArg}";
        if (!enabled) key.DeleteValue(ValueName, throwOnMissingValue: false);
        else if (key.GetValue(ValueName) as string != command) key.SetValue(ValueName, command);
    }
}
