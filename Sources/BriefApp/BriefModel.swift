import AppKit
import BriefCore
import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor @Observable
final class BriefModel {
    let store = BriefStore()
    let notifier = Notifier()

    private(set) var days: [String] = []
    var selectedDay: String? { didSet { loadSelectedBrief() } }
    private(set) var brief: DailyBrief?
    private(set) var collection: [SavedItem] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// Set while the launch intro plays over the window; a new value replays it.
    var introID: UUID?

    var savedIDs: Set<String> { Set(collection.map(\.id)) }
    var allTags: [String] { Array(Set(collection.flatMap(\.tags))).sorted() }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        reloadDays()
        selectedDay = days.first
        collection = store.loadCollection()
        startScheduling()
    }

    // MARK: Daily refresh

    /// Checks every 15 minutes, on wake and on activation. Cheap, and survives sleep through noon.
    private func startScheduling() {
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // The widget's save button writes to the same file.
                self?.collection = self?.store.loadCollection() ?? []
                await self?.notifier.refreshState()
                await self?.refreshIfDue()
            }
        })
        Task { await refreshIfDue() }
    }

    func refreshIfDue() async {
        guard Schedule.isDue(latestDay: days.first) else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let new = try await BriefBuilder().run(store: store)
            lastError = new.items.isEmpty ? "No items fetched — check your connection." : nil
            reloadDays()
            selectedDay = new.day
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Day navigation

    private func reloadDays() { days = store.availableDays() }

    private func loadSelectedBrief() { brief = selectedDay.flatMap(store.brief(for:)) }

    func canStep(_ delta: Int) -> Bool {
        guard let day = selectedDay, let i = days.firstIndex(of: day) else { return false }
        return days.indices.contains(i - delta)
    }

    /// delta -1 = older, +1 = newer (days are stored newest first).
    func step(_ delta: Int) {
        guard let day = selectedDay, let i = days.firstIndex(of: day), days.indices.contains(i - delta) else { return }
        selectedDay = days[i - delta]
    }

    // MARK: Collection

    func save(_ item: BriefItem) {
        mutate { items in
            guard !items.contains(where: { $0.id == item.id }) else { return }
            items.insert(SavedItem(item: item), at: 0)
        }
    }

    func remove(_ ids: Set<String>) {
        mutate { $0.removeAll { ids.contains($0.id) } }
    }

    func update(_ id: String, _ change: @escaping (inout SavedItem) -> Void) {
        // Tags, notes and read state aren't shown in the widget, so no widget reload.
        mutate(reloadWidget: false) { items in
            if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
        }
    }

    private func mutate(reloadWidget: Bool = true, _ change: @escaping (inout [SavedItem]) -> Void) {
        do {
            collection = try store.updateCollection(change)
            #if canImport(WidgetKit)
            if reloadWidget { WidgetCenter.shared.reloadAllTimelines() }
            #endif
        } catch {
            lastError = "Could not save collection: \(error.localizedDescription)"
        }
    }
}
