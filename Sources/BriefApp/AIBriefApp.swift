import AppKit
import SwiftUI

@main
struct AIBriefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AI Brief", systemImage: "sparkles.rectangle.stack") {
            MenuContent().environment(appDelegate.model)
        }

        Settings {
            SettingsView().environment(appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BriefModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainWindow.shared.model = model
        // The bundled app is a background agent (LSUIElement) and stays out of sight until asked.
        // A bare `swift run` executable has no Info.plist, so show it like a normal app there.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
            MainWindow.shared.show()
        }
    }

    /// The widget's Expand button opens aibrief://open.
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "aibrief" }) { MainWindow.shared.show() }
    }

    /// Keep running in the menu bar so the noon refresh happens even with the window closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The two-pane window, managed directly so it can be opened from a URL, the menu bar,
/// or at launch, whether or not it was shown before.
@MainActor
final class MainWindow {
    static let shared = MainWindow()
    var model: BriefModel?
    private var window: NSWindow?

    func show() {
        guard let model else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "AI Brief"
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 860, height: 520)
            w.contentView = NSHostingView(rootView: MainView().environment(model))
            if !w.setFrameUsingName("AIBriefMain") { w.center() }
            w.setFrameAutosaveName("AIBriefMain")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
