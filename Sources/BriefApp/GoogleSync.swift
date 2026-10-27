import AppKit
import BriefCore
import BriefUI
import Foundation
import Network
import Observation
import Security

/// Keeps the collection the same on every device signed in to the same Google account, through
/// one file in the user's Google Drive (see `DriveFile`). Only official builds have it: they carry
/// the Google client the sign-in needs (`AppBrand.googleClient`).
///
/// Syncs at launch, when the app becomes active, every 15 minutes while it runs, and a few
/// seconds after each change.
@MainActor @Observable
final class GoogleSync {
    enum State: Equatable {
        case off
        case signingIn
        case syncing
        case on
        /// Signed out by Google (password change, access removed): needs signing in again.
        case needsSignIn
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var email: String?
    private(set) var lastSync: Date?

    /// Called when a sync changed the local collection.
    @ObservationIgnored var onCollectionChanged: () -> Void = {}

    @ObservationIgnored private let store: BriefStore
    @ObservationIgnored private let oauth: GoogleOAuth?
    @ObservationIgnored private let tokens = TokenCache()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running = false

    private static let emailKey = "syncEmail", lastSyncKey = "syncLast"

    var isAvailable: Bool { oauth != nil }

    init(store: BriefStore) {
        self.store = store
        oauth = AppBrand.googleClient.map { GoogleOAuth(clientID: $0.id, clientSecret: $0.secret) }
        if oauth != nil, Keychain.refreshToken != nil {
            state = .on
            email = UserDefaults.standard.string(forKey: Self.emailKey)
            lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        }
    }

    var isOn: Bool { ![.off, .signingIn].contains(state) }

    // MARK: Sign-in

    private var signInTask: Task<Void, Never>?

    /// Opens Google's sign-in in the browser and waits for it to send the browser back.
    func signIn() {
        guard let oauth, state != .signingIn else { return }
        state = .signingIn
        lastSignInError = nil
        signInTask = Task {
            do {
                let receiver = try await LoopbackReceiver.start()
                let attempt = oauth.begin(redirectURI: receiver.redirectURI, scope: DriveFile.scope)
                NSWorkspace.shared.open(attempt.authorizationURL)
                let reply = try await receiver.waitForReply(timeout: 300)
                guard reply["state"] == attempt.state, let code = reply["code"] else {
                    throw SignInError(reply["error"] == "access_denied" ? nil : "Google didn't sign you in.")
                }
                let t = try await oauth.exchange(code: code, for: attempt)
                guard let refresh = t.refreshToken else { throw SignInError("Google didn't keep you signed in. Try again.") }
                Keychain.refreshToken = refresh
                await tokens.set(t)
                state = .on
                NSApp.activate()
                email = try? await DriveFile(accessToken: accessToken).email()
                UserDefaults.standard.set(email, forKey: Self.emailKey)
                await sync()
            } catch let error as SignInError {
                state = .off
                lastSignInError = error.message
            } catch is CancellationError {
                state = .off
            } catch {
                state = .off
                lastSignInError = error.localizedDescription
            }
        }
    }

    /// Shown under the button after a failed sign-in.
    private(set) var lastSignInError: String?

    func cancelSignIn() {
        signInTask?.cancel()
        state = .off
    }

    func signOut() {
        pending?.cancel()
        if let token = Keychain.refreshToken { Task.detached { await GoogleOAuth.revoke(token) } }
        Keychain.refreshToken = nil
        Task { await tokens.clear() }
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
        email = nil
        lastSync = nil
        state = .off
    }

    // MARK: Syncing

    /// After a change: syncs a few seconds later, so quick edits (typing a note) go up together.
    func syncSoon() {
        guard isOn else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    func sync() async {
        guard isOn, !running else { return }
        running = true
        state = .syncing
        defer { running = false }
        do {
            let outcome = try await CollectionSyncer(store: store, remote: DriveFile(accessToken: accessToken)).sync()
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: Self.lastSyncKey)
            state = .on
            if outcome.changedLocally { onCollectionChanged() }
        } catch is DriveAuthError {
            state = .needsSignIn
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// A current access token, refreshed with the keychain's refresh token when needed.
    private var accessToken: @Sendable () async throws -> String {
        { [oauth, tokens] in
            if let cached = await tokens.valid() { return cached }
            guard let oauth, let refresh = Keychain.refreshToken else { throw DriveAuthError() }
            let t = try await oauth.refresh(refresh)
            await tokens.set(t)
            return t.accessToken
        }
    }
}

private struct SignInError: Error {
    /// nil: the user cancelled, nothing to show.
    let message: String?
    init(_ message: String?) { self.message = message }
}

/// The current access token (an hour long), in memory only.
private actor TokenCache {
    private var tokens: GoogleOAuth.Tokens?
    func valid() -> String? { tokens.flatMap { $0.expiresAt > .now ? $0.accessToken : nil } }
    func set(_ t: GoogleOAuth.Tokens) { tokens = t }
    func clear() { tokens = nil }
}

/// The Google refresh token, in the login keychain (it stays signed in across launches).
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mmfreitas.aibrief.google-sync",
        kSecAttrAccount as String: "refresh-token",
    ]

    static var refreshToken: String? {
        get {
            var q = query
            q[kSecReturnData as String] = true
            var result: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let newValue else { return }
            var q = query
            q[kSecValueData as String] = Data(newValue.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}

/// Receives the browser's return from Google's sign-in on http://127.0.0.1:<port>/ and answers
/// with a short page telling the user to go back to the app.
private final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let port: UInt16
    private var continuation: CheckedContinuation<[String: String], Error>?
    private let lock = NSLock()

    var redirectURI: String { "http://127.0.0.1:\(port)/" }

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> LoopbackReceiver {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        let queue = DispatchQueue(label: "sign-in listener")
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            // State updates arrive on the serial queue, so `pending` is only touched there.
            nonisolated(unsafe) var pending: CheckedContinuation<UInt16, Error>? = cont
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: pending?.resume(returning: listener.port?.rawValue ?? 0); pending = nil
                case .failed(let e): pending?.resume(throwing: e); pending = nil
                default: break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        let receiver = LoopbackReceiver(listener: listener, port: port)
        listener.newConnectionHandler = { [receiver] in receiver.handle($0) }
        return receiver
    }

    func waitForReply(timeout: TimeInterval) async throws -> [String: String] {
        defer { listener.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                lock.withLock { continuation = cont }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.failure(SignInError("Sign-in timed out. Try again.")))
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        let cont = lock.withLock { () -> CheckedContinuation<[String: String], Error>? in
            defer { continuation = nil }
            return continuation
        }
        cont?.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // "GET /?state=…&code=… HTTP/1.1"
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let items = URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? []
            let reply = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            let ok = reply["code"] != nil
            let body = """
                <!doctype html><meta charset="utf-8"><title>\(AppBrand.displayName)</title>
                <body style="font: 16px -apple-system, system-ui, sans-serif; text-align: center; padding: 15vh 2em">
                <h2>\(ok ? "You're signed in" : "Sign-in didn't finish")</h2>
                <p>\(ok ? "You can close this tab and go back to \(AppBrand.displayName)." : "Go back to \(AppBrand.displayName) and try again.")</p>
                """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            // Browsers also ask for /favicon.ico; only the redirect carries state.
            if reply["state"] != nil { self?.finish(.success(reply)) }
        }
    }
}
