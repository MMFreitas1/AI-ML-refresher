import Foundation

/// Plain JSON files on disk:
///
///     <dir>/briefs/2026-10-08.json   one ranked list per day (kept as history)
///     <dir>/collection.json          saved items with tags, notes and read state
///     <dir>/deleted.json             when each removed item was removed, so removals sync
///
/// `<dir>` is the shared App Group container when the app and widget are built with Xcode,
/// so both read the same files. Without one (e.g. `swift run`) it falls back to Application Support.
public final class BriefStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    public static let appGroupKey = "AppGroupIdentifier"

    public init(directory: URL? = nil) {
        let fm = FileManager.default
        if let directory {
            self.directory = directory
        } else {
            let base: URL
            if let group = Bundle.main.object(forInfoDictionaryKey: Self.appGroupKey) as? String,
               let container = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
                base = container
            } else {
                base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            }
            self.directory = base.appendingPathComponent("Refresher", isDirectory: true)
            // Data from versions that used the folder name "AIBrief" moves over once.
            let legacy = base.appendingPathComponent("AIBrief", isDirectory: true)
            if !fm.fileExists(atPath: self.directory.path), fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: self.directory)
            }
        }
        try? fm.createDirectory(at: briefsDirectory, withIntermediateDirectories: true)
    }

    private var briefsDirectory: URL { directory.appendingPathComponent("briefs", isDirectory: true) }
    private var collectionURL: URL { directory.appendingPathComponent("collection.json") }
    private var deletedURL: URL { directory.appendingPathComponent("deleted.json") }

    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Briefs

    public func save(_ brief: DailyBrief) throws {
        try encoder.encode(brief).write(to: briefsDirectory.appendingPathComponent("\(brief.day).json"), options: .atomic)
    }

    public func brief(for day: String) -> DailyBrief? {
        guard let data = try? Data(contentsOf: briefsDirectory.appendingPathComponent("\(day).json")) else { return nil }
        return try? decoder.decode(DailyBrief.self, from: data)
    }

    /// Days with a saved brief, newest first.
    public func availableDays() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: briefsDirectory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted(by: >)
    }

    public func latestBrief() -> DailyBrief? {
        availableDays().lazy.compactMap(brief(for:)).first
    }

    /// Item IDs shown in the `days` briefs before `day`, so the same repo isn't served again tomorrow.
    public func seenIDs(before day: String, days: Int = 7) -> Set<String> {
        Set(availableDays().filter { $0 < day }.prefix(days).compactMap(brief(for:)).flatMap { $0.items.map(\.id) })
    }

    // MARK: Collection

    public func loadCollection() -> [SavedItem] {
        lock.withLock { readCollection() }
    }

    /// Read-modify-write so the app and the widget's "save" button don't overwrite each other.
    /// Changed items get a new `updatedAt` and removed ones a deletion time, for syncing.
    /// (The widget runs in its own process; the files are written atomically.)
    @discardableResult
    public func updateCollection(now: Date = SyncClock.now, _ mutate: (inout [SavedItem]) -> Void) throws -> [SavedItem] {
        try lock.withLock {
            let before = Dictionary(readCollection().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var items = readCollection()
            mutate(&items)
            for i in items.indices where before[items[i].id] != items[i] {
                items[i].updatedAt = now
            }
            var deleted = readDeleted()
            let kept = Set(items.map(\.id))
            let removed = before.keys.filter { !kept.contains($0) }
            if !removed.isEmpty || kept.contains(where: { deleted[$0] != nil }) {
                for id in removed { deleted[id] = now }
                for id in kept { deleted[id] = nil }
                try encoder.encode(deleted).write(to: deletedURL, options: .atomic)
            }
            try encoder.encode(items).write(to: collectionURL, options: .atomic)
            return items
        }
    }

    /// Removed item IDs and when they were removed.
    public func loadDeleted() -> [String: Date] {
        lock.withLock { readDeleted() }
    }

    /// Applies a sync: merges `remote` into the collection under the lock, without re-stamping, and
    /// returns the merged state. Local changes made meanwhile are part of the merge, not lost.
    @discardableResult
    public func mergeCollection(_ remote: SyncSnapshot) throws -> SyncSnapshot {
        try lock.withLock {
            let merged = CollectionSync.merge(SyncSnapshot(items: readCollection(), deleted: readDeleted()), remote)
            try encoder.encode(merged.deleted).write(to: deletedURL, options: .atomic)
            try encoder.encode(merged.items).write(to: collectionURL, options: .atomic)
            return merged
        }
    }

    private func readCollection() -> [SavedItem] {
        guard let data = try? Data(contentsOf: collectionURL) else { return [] }
        return (try? decoder.decode([SavedItem].self, from: data)) ?? []
    }

    private func readDeleted() -> [String: Date] {
        guard let data = try? Data(contentsOf: deletedURL) else { return [:] }
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }
}

public extension BriefStore {
    /// Adds the item if it isn't saved yet. Returns false when it was already there.
    @discardableResult
    func save(item: BriefItem) throws -> Bool {
        var added = false
        try updateCollection { items in
            guard !items.contains(where: { $0.id == item.id }) else { return }
            items.insert(SavedItem(item: item), at: 0)
            added = true
        }
        return added
    }
}
