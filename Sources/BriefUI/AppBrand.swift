import SwiftUI
#if canImport(PrivateBrand)
import PrivateBrand
#endif

/// The app's look: name, icon, widget badge and launch intro.
///
/// Official releases are built with a private brand package (`Brand/`, not part of this
/// repository; see BRAND.md). Without it, everything here falls back to a neutral look, so the
/// project builds and runs as-is.
public enum AppBrand {
    #if canImport(PrivateBrand)
    public static let isBranded = true
    #else
    public static let isBranded = false
    #endif

    /// The built app's display name (set by the build, see `APP_DISPLAY_NAME` in project.yml).
    public static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "AI-ML Refresher"
    }

    /// Loads brand resources (fonts). Call once at launch.
    public static func prepare() {
        #if canImport(PrivateBrand)
        BrandKit.prepare()
        #endif
    }

    /// Whether there is a launch intro to play.
    public static var hasIntro: Bool { isBranded }

    /// The launch intro. Loops while `isReady` is false, then calls `onFinish`.
    @ViewBuilder
    public static func intro(isReady: Bool, onFinish: @escaping () -> Void) -> some View {
        #if canImport(PrivateBrand)
        BrandKit.intro(isReady: isReady, onFinish: onFinish)
        #else
        Color.clear.onAppear(perform: onFinish)
        #endif
    }

    /// One frame of the intro at `t` seconds, for previews. Nil without a brand.
    public static func introFrame(at t: Double) -> AnyView? {
        #if canImport(PrivateBrand)
        return BrandKit.introFrame(at: t)
        #else
        return nil
        #endif
    }

    /// Signature in the widget's lower-right corner. Nothing without a brand.
    @ViewBuilder
    public static func widgetBadge(large: Bool) -> some View {
        #if canImport(PrivateBrand)
        BrandKit.widgetBadge(large: large)
        #endif
    }

    /// App icon artwork (a rounded tile; the build places it on the macOS icon grid).
    @ViewBuilder
    public static func appIcon() -> some View {
        #if canImport(PrivateBrand)
        BrandKit.appIcon()
        #else
        NeutralAppIcon()
        #endif
    }
}

/// Plain icon for unbranded builds.
struct NeutralAppIcon: View {
    var body: some View {
        GeometryReader { g in
            let side = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkles.rectangle.stack")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(width: side * 0.52)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
