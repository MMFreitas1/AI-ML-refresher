import BriefCore
import SwiftUI

struct MainView: View {
    var body: some View {
        HSplitView {
            DayPane()
                .frame(minWidth: 420, idealWidth: 560, maxHeight: .infinity, alignment: .top)
            CollectionPane()
                .frame(minWidth: 360, idealWidth: 480, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Left: today's items

struct DayPane: View {
    @Environment(BriefModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let brief = model.brief, !brief.items.isEmpty {
                List {
                    ForEach(Array(brief.items.enumerated()), id: \.element.id) { index, item in
                        BriefRow(rank: index + 1, item: item, isSaved: model.savedIDs.contains(item.id))
                            .draggable(DragPayload.encode(item)) {
                                Label(item.title, systemImage: item.field.symbol).padding(6)
                            }
                    }
                }
                .listStyle(.inset)
            } else {
                ContentUnavailableView {
                    Label(model.isRefreshing ? "Fetching today's brief…" : "No brief yet",
                          systemImage: "sparkles.rectangle.stack")
                } description: {
                    Text(model.lastError ?? "A new brief is built every day after 12:00.")
                } actions: {
                    Button("Fetch now") { Task { await model.refresh() } }
                        .disabled(model.isRefreshing)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canStep(-1)).help("Previous day")
            VStack(alignment: .leading, spacing: 1) {
                Text(dayTitle).font(.headline)
                if let brief = model.brief {
                    Text("\(brief.items.count) items · built \(brief.generatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canStep(1)).help("Next day")
            Spacer()
            if let errors = model.brief?.errors, !errors.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Some sources failed:\n" + errors.joined(separator: "\n"))
            }
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Rebuild today's brief now")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var dayTitle: String {
        guard let day = model.selectedDay else { return "Today" }
        if day == Day.string(for: .now) { return "Today" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return day }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

struct BriefRow: View {
    @Environment(BriefModel.self) private var model
    @Environment(\.openURL) private var openURL
    let rank: Int
    let item: BriefItem
    let isSaved: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(rank <= 5 ? Color.accentColor : .secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                FieldChip(field: item.field)
                Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("\(item.source) · \(item.metric)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button { model.save(item) } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.borderless)
            .disabled(isSaved)
            .help(isSaved ? "In your collection" : "Save to collection (or drag it right)")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openURL(item.url) }
        .contextMenu { ItemLinksMenu(item: item, onSave: isSaved ? nil : { model.save(item) }) }
    }
}

// MARK: - Right: collection

struct CollectionPane: View {
    enum ReadFilter: String, CaseIterable { case all = "All", unread = "Unread", read = "Read" }

    @Environment(BriefModel.self) private var model
    @State private var selection: String?
    @State private var search = ""
    @State private var tag: String?
    @State private var readFilter = ReadFilter.all
    @State private var isDropTarget = false

    private var filtered: [SavedItem] {
        model.collection.filter { saved in
            (tag == nil || saved.tags.contains(tag!))
                && (readFilter == .all || saved.isRead == (readFilter == .read))
                && (search.isEmpty || [saved.item.title, saved.item.summary, saved.note, saved.tags.joined(separator: " ")]
                    .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.collection.isEmpty {
                ContentUnavailableView("Drag items here", systemImage: "tray.and.arrow.down",
                                       description: Text("Your collection is kept across days, with tags, notes and read state."))
            } else {
                VSplitView {
                    List(filtered, selection: $selection) { saved in
                        CollectionRow(saved: saved).tag(saved.id)
                            .contextMenu {
                                Button(saved.isRead ? "Mark as Unread" : "Mark as Read") {
                                    model.update(saved.id) { $0.isRead.toggle() }
                                }
                                ItemLinksMenu(item: saved.item, onSave: nil)
                                Divider()
                                Button("Remove from Collection", role: .destructive) { model.remove([saved.id]) }
                            }
                    }
                    .listStyle(.inset)
                    .onDeleteCommand { if let selection { model.remove([selection]) } }
                    .frame(minHeight: 180)

                    if let id = selection, let saved = model.collection.first(where: { $0.id == id }) {
                        CollectionEditor(saved: saved).id(id).frame(minHeight: 170)
                    }
                }
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .background(Color.accentColor.opacity(0.06))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { payloads, _ in
            let items = payloads.compactMap(DragPayload.decode)
            items.forEach(model.save)
            if let first = items.first { selection = first.id }
            return !items.isEmpty
        } isTargeted: { isDropTarget = $0 }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Collection").font(.headline)
                Text("\(model.collection.count)").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Picker("", selection: $readFilter) {
                    ForEach(ReadFilter.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).fixedSize()
            }
            HStack {
                TextField("Search title, notes, tags", text: $search).textFieldStyle(.roundedBorder)
                Menu {
                    Button("All tags") { tag = nil }
                    if !model.allTags.isEmpty { Divider() }
                    ForEach(model.allTags, id: \.self) { t in Button(t) { tag = t } }
                } label: {
                    Label(tag ?? "Tags", systemImage: "tag")
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct CollectionRow: View {
    @Environment(BriefModel.self) private var model
    let saved: SavedItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.update(saved.id) { $0.isRead.toggle() } } label: {
                Image(systemName: saved.isRead ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(saved.isRead ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(saved.isRead ? "Mark as unread" : "Mark as read")
            VStack(alignment: .leading, spacing: 3) {
                Text(saved.item.title).fontWeight(saved.isRead ? .regular : .semibold).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: saved.item.field.symbol)
                    Text("\(saved.item.source) · saved \(saved.savedAt.formatted(date: .abbreviated, time: .omitted))")
                }
                .font(.caption).foregroundStyle(.secondary)
                if !saved.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(saved.tags, id: \.self) { t in
                            Text(t).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                }
                if !saved.note.isEmpty {
                    Text(saved.note).font(.caption).foregroundStyle(.secondary).lineLimit(1).italic()
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct CollectionEditor: View {
    @Environment(BriefModel.self) private var model
    @Environment(\.openURL) private var openURL
    let saved: SavedItem
    @State private var tagsText = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(saved.item.title).font(.headline).lineLimit(1)
                Spacer()
                Button("Open") { openURL(saved.item.url) }
                if let d = saved.item.discussionURL {
                    Button("Discussion") { openURL(d) }
                }
            }
            TextField("Tags, comma separated (e.g. rl, to-try, paper)", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitTags)
            TextEditor(text: $note)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("Notes: why it matters, what to try…").foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                    }
                }
                .onChange(of: note) { _, new in model.update(saved.id) { $0.note = new } }
        }
        .padding(12)
        .onAppear {
            tagsText = saved.tags.joined(separator: ", ")
            note = saved.note
        }
        .onDisappear(perform: commitTags)
    }

    private func commitTags() {
        var seen = Set<String>()
        let tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard tags != saved.tags else { return }
        model.update(saved.id) { $0.tags = tags }
    }
}

// MARK: - Shared pieces

struct FieldChip: View {
    let field: Field
    var body: some View {
        Label(field.rawValue, systemImage: field.symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

struct ItemLinksMenu: View {
    @Environment(\.openURL) private var openURL
    let item: BriefItem
    let onSave: (() -> Void)?

    var body: some View {
        Button("Open Link") { openURL(item.url) }
        if let d = item.discussionURL { Button("Open Discussion") { openURL(d) } }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
        }
        if let onSave { Button("Save to Collection", action: onSave) }
    }
}

/// Items are dragged as JSON text so the drop side gets the full item, from any day.
enum DragPayload {
    static let prefix = "aibrief-item:"

    static func encode(_ item: BriefItem) -> String {
        let data = (try? JSONEncoder().encode(item)) ?? Data()
        return prefix + data.base64EncodedString()
    }

    static func decode(_ string: String) -> BriefItem? {
        guard string.hasPrefix(prefix), let data = Data(base64Encoded: String(string.dropFirst(prefix.count))) else { return nil }
        return try? JSONDecoder().decode(BriefItem.self, from: data)
    }
}
