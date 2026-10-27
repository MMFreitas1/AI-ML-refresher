import BriefCore
import BriefUI
import ServiceManagement
import SwiftUI

/// The background helper (a login item inside the app) that builds the brief at noon and
/// keeps the widget current while the app is closed.
enum BackgroundAgent {
    static let identifier = "com.mmfreitas.aibrief.helper"
    /// The helper's ID in earlier versions; its login item is removed on launch.
    private static let legacyIdentifier = "com.mmfreitas.aibrief.agent"
    private static let key = "backgroundRefresh"

    static var isWanted: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Only the bundled app has a helper; `swift run` doesn't.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var status: SMAppService.Status { SMAppService.loginItem(identifier: identifier).status }

    /// Which copy of the helper is registered: re-register when the app moves or updates, since
    /// launchd keeps the path it was given (re-registering every launch would repeat macOS's
    /// "background item added" notice).
    private static let registeredKey = "backgroundHelperRegisteredFor"
    private static var currentBuild: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let helpers = (try? FileManager.default.contentsOfDirectory(
            atPath: Bundle.main.bundlePath + "/Contents/Library/LoginItems"))?.sorted().joined(separator: ",") ?? ""
        return "\(Bundle.main.bundlePath)#\(version)#\(helpers)"
    }

    /// Registers or unregisters the helper to match the setting. Registering also starts it.
    static func apply() throws {
        guard isAvailable else { return }
        let service = SMAppService.loginItem(identifier: identifier)
        let defaults = UserDefaults.standard
        if isWanted {
            // Re-register when this copy changed, or when the helper isn't running even though it's
            // enabled (launchd still pointing at a copy that was moved or replaced).
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
            let stale = defaults.string(forKey: registeredKey) != currentBuild
                || (service.status == .enabled && !running)
            if stale && service.status == .enabled { try? service.unregister() }
            if stale || service.status != .enabled {
                try service.register()
                defaults.set(currentBuild, forKey: registeredKey)
            }
        } else if service.status == .enabled {
            try service.unregister()
            defaults.removeObject(forKey: registeredKey)
        }
        // Earlier versions used another helper ID, or registered the whole app at login
        // (which now would open its window). Clean both up.
        let legacy = SMAppService.loginItem(identifier: legacyIdentifier)
        if legacy.status != .notRegistered { try? legacy.unregister() }
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
    }
}

struct SettingsView: View {
    @Environment(BriefModel.self) private var model
    @State private var background = BackgroundAgent.isWanted
    @State private var backgroundStatus = BackgroundAgent.status
    @State private var backgroundError: String?
    @AppStorage(Intro.key) private var playIntro = true

    var body: some View {
        Form {
            Section {
                Toggle("Refresh in the background", isOn: $background)
                    .disabled(!BackgroundAgent.isAvailable)
                    .onChange(of: background) { _, on in
                        BackgroundAgent.isWanted = on
                        do { try BackgroundAgent.apply(); backgroundError = nil }
                        catch { backgroundError = error.localizedDescription }
                        backgroundStatus = BackgroundAgent.status
                    }
                Text("Builds the brief after 12:00 and keeps the widget current, even with \(AppBrand.displayName) closed.")
                    .font(.caption).foregroundStyle(.secondary)
                if background && backgroundStatus == .requiresApproval {
                    Button("Allow in System Settings → Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let backgroundError { Text(backgroundError).font(.caption).foregroundStyle(.red) }
            }
            if model.sync.isAvailable { SyncSection(sync: model.sync) }
            if AppBrand.hasIntro {
                Section("Appearance") {
                    Toggle("Play intro animation at launch", isOn: $playIntro)
                }
            }
            Section("Notifications") {
                LabeledContent("Daily at 12:05") {
                    switch model.notifier.state {
                    case .on: Button("Turn Off") { Task { await model.notifier.toggle() } }
                    case .off: Button("Turn On") { Task { await model.notifier.toggle() } }
                    case .deniedInSystemSettings: Button("Open System Settings…") { Task { await model.notifier.toggle() } }
                    case .unavailable: Text("Only in the installed app").foregroundStyle(.secondary)
                    }
                }
                if model.notifier.state == .on {
                    Button("Send Test Notification") { model.notifier.sendTest() }
                }
            }
            Section("Schedule") {
                LabeledContent("New brief", value: "Daily after \(Schedule.refreshHour):00 local time")
                LabeledContent("Next check", value: Schedule.nextRefresh().formatted(date: .abbreviated, time: .shortened))
            }
            Section("Data") {
                LabeledContent("Folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) }
                }
                LabeledContent("Saved items", value: "\(model.collection.count)")
                LabeledContent("Days of history", value: "\(model.days.count)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
