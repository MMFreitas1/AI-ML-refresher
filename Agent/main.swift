import AppKit
import BriefCore
import WidgetKit

/// The app's background helper: a faceless login item embedded in the app
/// (Contents/Library/LoginItems). It builds the daily brief after 12:00 and refreshes the widget,
/// so the app itself can quit when its window closes and launch normally (Dock bounce) each time.
@MainActor
final class Agent: NSObject, NSApplicationDelegate {
    private let store = BriefStore()
    private var isRefreshing = false
    private var timers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit quietly quits windowless apps when idle; this helper must stay up to wait for noon.
        ProcessInfo.processInfo.disableAutomaticTermination("Waiting for the daily refresh")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Exactly at noon, every 15 minutes as a fallback, and on wake (a Mac asleep at noon).
        scheduleNoon()
        timers.append(Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        Task { await refreshIfDue() }
    }

    private func scheduleNoon() {
        let timer = Timer(fire: Schedule.nextRefresh(), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshIfDue()
                self?.scheduleNoon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    private func refreshIfDue() async {
        guard !isRefreshing, Schedule.isDue(latestDay: store.latestBrief()?.day) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // A failed run saves nothing, so the brief stays due and the next check retries.
        if let brief = try? await BriefBuilder().run(store: store), !brief.items.isEmpty {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let agent = Agent()
    app.delegate = agent
    app.setActivationPolicy(.prohibited)
    withExtendedLifetime(agent) { app.run() }
}
