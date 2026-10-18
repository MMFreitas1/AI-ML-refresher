import BriefCore
import ServiceManagement
import SwiftUI

struct MenuContent: View {
    @Environment(BriefModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let top = Array((model.days.first.flatMap(model.store.brief(for:))?.items ?? []).prefix(5))
        if top.isEmpty {
            Text("No brief yet")
        } else {
            Text("Today's top 5")
            ForEach(top) { item in
                Button("\(item.title)  —  \(item.source)") { openURL(item.url) }
            }
        }
        Divider()
        Button("Open AI Brief") {
            MainWindow.shared.show()
        }
        .keyboardShortcut("o")
        Button(model.isRefreshing ? "Refreshing…" : "Refresh Now") { Task { await model.refresh() } }
            .disabled(model.isRefreshing)
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit AI Brief") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @Environment(BriefModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login (keeps the daily refresh running)", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Only available in the built .app: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
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
