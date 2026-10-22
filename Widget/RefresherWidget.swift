import AppIntents
import BriefCore
import BriefUI
import SwiftUI
import WidgetKit

// The widget only reads what the app wrote to the shared App Group folder; the app does the fetching.

struct BriefEntry: TimelineEntry {
    let date: Date
    let day: String?
    let items: [BriefItem]
    let savedIDs: Set<String>
}

struct BriefProvider: TimelineProvider {
    func placeholder(in context: Context) -> BriefEntry {
        BriefEntry(date: .now, day: nil, items: Self.sample, savedIDs: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefEntry) -> Void) {
        let entry = load()
        completion(entry.items.isEmpty && context.isPreview ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefEntry>) -> Void) {
        // The background helper reloads the widget right after it builds a new brief; this is the
        // fallback. Past noon without today's brief, look again soon instead of waiting a day.
        let entry = load()
        let next = Schedule.isDue(latestDay: entry.day)
            ? Date.now.addingTimeInterval(15 * 60)
            : Schedule.nextRefresh().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> BriefEntry {
        let store = BriefStore()
        let brief = store.latestBrief()
        return BriefEntry(date: .now, day: brief?.day, items: Array((brief?.items ?? []).prefix(5)),
                          savedIDs: Set(store.loadCollection().map(\.id)))
    }

    static let sample: [BriefItem] = (1...5).map {
        BriefItem(url: URL(string: "https://example.com/\($0)")!, title: "Trending AI item \($0)",
                  summary: "Short description of the item.", kind: .hfPapers, source: "HF Papers",
                  metric: "\(200 - $0 * 30) upvotes", rawScore: 1)
    }
}

/// The bookmark button on each row. Runs inside the widget process and writes the shared collection.
struct ToggleSaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Save to collection"
    static var isDiscoverable = false

    @Parameter(title: "Item ID") var itemID: String

    init() {}
    init(itemID: String) { self.itemID = itemID }

    func perform() async throws -> some IntentResult {
        let store = BriefStore()
        guard let item = store.latestBrief()?.items.first(where: { $0.id == itemID }) else { return .result() }
        try store.updateCollection { items in
            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items.remove(at: i)
            } else {
                items.insert(SavedItem(item: item), at: 0)
            }
        }
        return .result()
    }
}

struct BriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BriefEntry

    var body: some View {
        BriefWidgetContent(day: entry.day, items: entry.items, savedIDs: entry.savedIDs,
                           isLarge: family == .systemLarge || family == .systemExtraLarge) { item, isSaved in
            Button(intent: ToggleSaveIntent(itemID: item.id)) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RefresherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RefresherWidget", provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(AppBrand.displayName))
        .description("Today's top 5 in AI & ML. Refreshes daily after 12:00.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct RefresherWidgetBundle: WidgetBundle {
    var body: some Widget { RefresherWidget() }
}
