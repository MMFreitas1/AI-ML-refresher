import AppKit
import BriefCore
import BriefUI
import Observation
import UserNotifications

/// The daily "new brief" notification: opt-in from the bell button. It's scheduled with macOS
/// (12:05 every day, just after the background helper builds the brief), so it arrives even
/// while the app is closed. Clicking it launches the app.
@MainActor @Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum State { case off, on, deniedInSystemSettings, unavailable }

    private(set) var state: State = .off

    private static let enabledKey = "notificationsEnabled"
    @ObservationIgnored private var wantsNotifications: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// Notifications need a real app bundle; a bare `swift run` executable has none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    override init() {
        super.init()
        center?.delegate = self
        Task { await refreshState() }
    }

    /// Re-reads the system permission, which can change in System Settings at any time,
    /// and keeps the scheduled daily notification in line with it.
    func refreshState() async {
        guard let center else { state = .unavailable; return }
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .denied: state = wantsNotifications ? .deniedInSystemSettings : .off
        case .authorized, .provisional: state = wantsNotifications ? .on : .off
        default: state = .off
        }
        syncSchedule()
    }

    private static let dailyID = "daily-brief"

    private func syncSchedule() {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyID])
        guard state == .on else { return }
        let time = DateComponents(hour: Schedule.refreshHour, minute: 5)
        center.add(UNNotificationRequest(identifier: Self.dailyID, content: content(),
                                         trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)))
    }

    private func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Most recent AI & ML trends for you"
        content.body = "Today's top picks are ready in \(AppBrand.displayName)."
        content.sound = .default
        return content
    }

    func sendTest() {
        guard state == .on, let center else { return }
        center.add(UNNotificationRequest(identifier: "test", content: content(), trigger: nil))
    }

    /// The bell button.
    func toggle() async {
        guard let center else { return }
        switch state {
        case .on:
            wantsNotifications = false
        case .off:
            wantsNotifications = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        case .deniedInSystemSettings:
            // macOS only asks once; after a "Don't Allow" the switch lives in System Settings.
            let id = Bundle.main.bundleIdentifier ?? ""
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                NSWorkspace.shared.open(url)
            }
        case .unavailable:
            break
        }
        await refreshState()
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { MainWindow.shared.show() }
    }
}
