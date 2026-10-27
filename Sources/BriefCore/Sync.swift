import Foundation

/// Seconds precision, like the stored dates, so a value compares equal after a round trip.
public enum SyncClock {
    public static var now: Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }
}

/// A collection plus its removals: what is synced.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public var items: [SavedItem]
    public var deleted: [String: Date]

    public init(items: [SavedItem] = [], deleted: [String: Date] = [:]) {
        self.items = items
        self.deleted = deleted
    }

    /// Content comparison, independent of order.
    public func sameAs(_ other: SyncSnapshot) -> Bool {
        CollectionSync.merge(self, SyncSnapshot()) == CollectionSync.merge(other, SyncSnapshot())
    }
}

/// Merging two copies of the collection (this device's and the synced file). Same rules in the
/// Windows and Android apps, so any device can merge with any other:
///
/// - Per item, the copy changed last (`updatedAt`, else `savedAt`) wins. Ties keep the first argument's.
/// - A removal wins over copies changed at or before it; an item saved again later comes back.
/// - Removal times are kept (the latest per item) so a removal reaches devices that sync later.
/// - The result is ordered newest saved first, like the collection itself.
public enum CollectionSync {
    public static func merge(_ local: SyncSnapshot, _ remote: SyncSnapshot) -> SyncSnapshot {
        var deleted = local.deleted.merging(remote.deleted) { max($0, $1) }
        var byID: [String: SavedItem] = [:]
        for item in local.items + remote.items {
            if let existing = byID[item.id], item.changedAt <= existing.changedAt { continue }
            byID[item.id] = item
        }
        let items = byID.values
            .filter { item in deleted[item.id].map { item.changedAt > $0 } ?? true }
            .sorted { $0.savedAt != $1.savedAt ? $0.savedAt > $1.savedAt : $0.id < $1.id }
        // An item that outlived its removal no longer needs the removal record.
        for item in items { deleted[item.id] = nil }
        return SyncSnapshot(items: items, deleted: deleted)
    }
}

/// Where the synced copy lives. `DriveFile` in the app; a fake in tests.
public protocol RemoteCollection: Sendable {
    func find() async throws -> String?
    func read(id: String) async throws -> SyncSnapshot
    func create(_ snapshot: SyncSnapshot) async throws -> String
    func update(id: String, _ snapshot: SyncSnapshot) async throws
}

/// One sync: download the synced copy, merge it into the local collection, upload the result if it changed.
public struct CollectionSyncer: Sendable {
    public struct Outcome: Sendable {
        public let items: Int
        public let uploaded: Bool
        /// The local collection changed (reload the UI and the widget).
        public let changedLocally: Bool
    }

    let store: BriefStore
    let remote: any RemoteCollection

    public init(store: BriefStore, remote: any RemoteCollection) {
        self.store = store
        self.remote = remote
    }

    public func sync() async throws -> Outcome {
        let id = try await remote.find()
        var theirs = SyncSnapshot()
        if let id { theirs = try await remote.read(id: id) }
        let before = SyncSnapshot(items: store.loadCollection(), deleted: store.loadDeleted())
        let merged = try store.mergeCollection(theirs)
        let upload = id == nil || !merged.sameAs(theirs)
        if upload {
            if let id { try await remote.update(id: id, merged) } else { _ = try await remote.create(merged) }
        }
        return Outcome(items: merged.items.count, uploaded: upload, changedLocally: !merged.sameAs(before))
    }
}

public struct DriveAuthError: LocalizedError {
    public init() {}
    public var errorDescription: String? { "Google sign-in expired" }
}

/// The synced copy of the collection: one JSON file (`SyncSnapshot`) in the user's Google Drive.
/// Uses only the `drive.file` permission (files the app created, nothing else). The file is found by
/// an app property rather than its name, so renaming or moving it in Drive doesn't break syncing.
public struct DriveFile: RemoteCollection {
    public static let scope = "https://www.googleapis.com/auth/drive.file"
    public static let fileName = "AI-ML Refresher library.json"
    static let property = "refresherCollection"
    static let api = "https://www.googleapis.com/drive/v3"
    static let upload = "https://www.googleapis.com/upload/drive/v3"

    /// Returns a current OAuth access token for the signed-in Google account.
    let accessToken: @Sendable () async throws -> String

    public init(accessToken: @Sendable @escaping () async throws -> String) {
        self.accessToken = accessToken
    }

    public func find() async throws -> String? {
        var c = URLComponents(string: "\(Self.api)/files")!
        c.queryItems = [
            URLQueryItem(name: "spaces", value: "drive"), URLQueryItem(name: "fields", value: "files(id)"),
            URLQueryItem(name: "orderBy", value: "createdTime"),
            URLQueryItem(name: "q", value: "appProperties has { key='\(Self.property)' and value='1' } and trashed=false"),
        ]
        struct Files: Decodable { struct F: Decodable { let id: String }; let files: [F] }
        return try JSONDecoder().decode(Files.self, from: await send("GET", c.url!)).files.first?.id
    }

    public func read(id: String) async throws -> SyncSnapshot {
        let data = try await send("GET", URL(string: "\(Self.api)/files/\(id)?alt=media")!)
        do { return try Self.decoder.decode(SyncSnapshot.self, from: data) } catch { throw FetchError.parse("the synced collection") }
    }

    public func create(_ snapshot: SyncSnapshot) async throws -> String {
        let boundary = "refresher-\(UUID().uuidString)"
        let metadata = #"{"name":"\#(Self.fileName)","mimeType":"application/json","appProperties":{"\#(Self.property)":"1"}}"#
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n\(metadata)\r\n".utf8)
        body += Data("--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8)
        body += try Self.encoder.encode(snapshot)
        body += Data("\r\n--\(boundary)--".utf8)
        struct Created: Decodable { let id: String }
        let data = try await send("POST", URL(string: "\(Self.upload)/files?uploadType=multipart&fields=id")!,
                                  body: body, type: "multipart/related; boundary=\(boundary)")
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    public func update(id: String, _ snapshot: SyncSnapshot) async throws {
        _ = try await send("PATCH", URL(string: "\(Self.upload)/files/\(id)?uploadType=media&fields=id")!,
                           body: try Self.encoder.encode(snapshot), type: "application/json")
    }

    /// The signed-in account's email address, shown in Settings.
    public func email() async throws -> String? {
        struct About: Decodable { struct U: Decodable { let emailAddress: String? }; let user: U? }
        let data = try await send("GET", URL(string: "\(Self.api)/about?fields=user(emailAddress)")!)
        return try JSONDecoder().decode(About.self, from: data).user?.emailAddress
    }

    private func send(_ method: String, _ url: URL, body: Data? = nil, type: String? = nil) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue(type, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw DriveAuthError() }
        guard (200..<300).contains(code) else { throw FetchError.status(code, "Google Drive") }
        return data
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
