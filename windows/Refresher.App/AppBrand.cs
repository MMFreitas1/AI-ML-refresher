using Avalonia;
using Avalonia.Controls;
using Avalonia.Platform;
#if PRIVATE_BRAND
using PrivateBrand;
#endif

namespace Refresher.App;

/// <summary>
/// The app's look: name, icon, fonts and launch intro.
///
/// Official releases are built with a private brand package (Brand/windows, not part of this
/// repository; see BRAND.md). Without it, everything here falls back to a neutral look, so the
/// project builds and runs as-is.
/// </summary>
public static class AppBrand
{
#if PRIVATE_BRAND
    public const bool IsBranded = true;
    public static string DisplayName => BrandKit.DisplayName;
#else
    public const bool IsBranded = false;
    public static string DisplayName => "AI-ML Refresher";
#endif

    /// <summary>Registers brand fonts with Avalonia. Called while the app is being built.</summary>
    public static AppBuilder Configure(AppBuilder builder)
    {
#if PRIVATE_BRAND
        return BrandKit.Configure(builder);
#else
        return builder;
#endif
    }

    /// <summary>Applies brand resources (accent colors, font family) to the app. Call once at launch.</summary>
    public static void Prepare(Application app)
    {
#if PRIVATE_BRAND
        BrandKit.Prepare(app);
#endif
    }

    /// <summary>Window and notification-area icon.</summary>
    public static WindowIcon Icon()
    {
#if PRIVATE_BRAND
        return new WindowIcon(BrandKit.OpenAppIcon());
#else
        return new WindowIcon(AssetLoader.Open(new Uri("avares://Refresher/Assets/AppIcon.png")));
#endif
    }

    /// <summary>Whether there is a launch intro to play.</summary>
    public static bool HasIntro => IsBranded;

    /// <summary>The launch intro. Loops while <paramref name="isReady"/> returns false, then calls <paramref name="onFinish"/>.</summary>
    public static Control? Intro(Func<bool> isReady, Action onFinish)
    {
#if PRIVATE_BRAND
        return BrandKit.Intro(isReady, onFinish);
#else
        return null;
#endif
    }
}
