import AppIntents
import BriefCore
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
        // The app also reloads the widget right after it builds a new brief; this is the fallback.
        let next = Schedule.nextRefresh().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [load()], policy: .after(next)))
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
    static var title: LocalizedStringResource = "Save to AI Brief collection"
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

    private var isLarge: Bool { family == .systemLarge || family == .systemExtraLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 4) {
            header
            if entry.items.isEmpty {
                Spacer()
                Text("Open AI Brief to fetch today's items.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.items.enumerated()), id: \.element.id) { i, item in
                    row(i + 1, item)
                    if isLarge && i < entry.items.count - 1 { Divider() }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var header: some View {
        HStack {
            Label("AI Brief", systemImage: "sparkles.rectangle.stack")
                .font(.caption.weight(.semibold))
            if let day = entry.day {
                Text(day).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // Opens the two-pane window (today ⇄ collection).
            Link(destination: URL(string: "aibrief://open")!) {
                Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.medium))
            }
        }
    }

    private func row(_ rank: Int, _ item: BriefItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 12)
            Link(destination: item.url) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(isLarge ? .callout.weight(.semibold) : .caption.weight(.medium))
                        .lineLimit(isLarge ? 2 : 1)
                    if isLarge {
                        HStack(spacing: 4) {
                            Image(systemName: item.field.symbol)
                            Text("\(item.field.rawValue) · \(item.source) · \(item.metric)")
                        }
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(intent: ToggleSaveIntent(itemID: item.id)) {
                Image(systemName: entry.savedIDs.contains(item.id) ? "bookmark.fill" : "bookmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
}

struct AIBriefWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIBriefWidget", provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Brief")
        .description("Today's top 5 in AI & ML. Refreshes daily after 12:00.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct AIBriefWidgetBundle: WidgetBundle {
    var body: some Widget { AIBriefWidget() }
}
