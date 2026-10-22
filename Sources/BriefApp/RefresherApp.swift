import AppKit
import BriefCore
import BriefUI
import SwiftUI

@main
struct RefresherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView().environment(appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BriefModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppBrand.prepare()
        MainWindow.shared.model = model
        // A normal app: it opens its window on launch and quits when the window closes.
        // The background helper does the noon refresh while it's closed.
        MainWindow.shared.show()
        do { try BackgroundAgent.apply() } catch { NSLog("\(AppBrand.displayName): background helper: \(error)") }
    }

    /// Clicking the Dock icon while the app is running but has no window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.shared.show()
        return false
    }

    /// The widget's Expand button opens aimlrefresher://open.
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "aimlrefresher" }) { MainWindow.shared.show() }
    }

    /// Closing the window quits, so the next click is a fresh launch (Dock bounce, intro).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// The two-pane window, managed directly so it can be opened at launch, from the widget's URL,
/// from a notification, or from the Dock.
@MainActor
final class MainWindow {
    static let shared = MainWindow()
    var model: BriefModel?
    private var window: NSWindow?
    private var hasShown = false

    func show() {
        guard let model else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = AppBrand.displayName
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 860, height: 520)
            w.contentView = NSHostingView(rootView: RootView().environment(model))
            if !w.setFrameUsingName("MainWindow") { w.center() }
            w.setFrameAutosaveName("MainWindow")
            window = w
        }
        // The intro plays on every launch, never when an already-running app is brought back.
        if !hasShown {
            hasShown = true
            if AppBrand.hasIntro && Intro.isEnabled { model.introID = UUID() }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The window's content: the two panes, with the brand intro fading into them.
struct RootView: View {
    @Environment(BriefModel.self) private var model

    var body: some View {
        ZStack {
            MainView()
            if let id = model.introID {
                // Fades in once the animation is home and today's brief has finished loading.
                AppBrand.intro(isReady: !model.isRefreshing) {
                    // --dur-slow with --ease-out, from the design system's motion tokens.
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)) { model.introID = nil }
                }
                .id(id)
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

/// The launch intro preference (Settings). On by default.
enum Intro {
    static let key = "playIntro"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}
