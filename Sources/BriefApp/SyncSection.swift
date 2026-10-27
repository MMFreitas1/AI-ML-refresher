import BriefUI
import SwiftUI

/// Settings → Sync: sign in once per device, with the same Google account, to share the collection.
struct SyncSection: View {
    let sync: GoogleSync

    var body: some View {
        Section("Sync") {
            switch sync.state {
            case .off, .signingIn:
                Text("Keep your collection the same on your Mac, PC and phone. Sign in with the same Google account on each one.")
                    .font(.caption).foregroundStyle(.secondary)
                if sync.state == .signingIn {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Finish signing in in your browser…")
                        Spacer()
                        Button("Cancel") { sync.cancelSignIn() }
                    }
                } else {
                    Button("Sync with Google…") { sync.signIn() }
                }
                if let error = sync.lastSignInError { Text(error).font(.caption).foregroundStyle(.red) }
            default:
                LabeledContent("Account", value: sync.email ?? "Google account")
                LabeledContent("Status") {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text(status).foregroundStyle(isProblem ? .red : .secondary)
                    }
                }
                HStack {
                    if sync.state == .needsSignIn {
                        Button("Sign In Again…") { sync.signIn() }
                    } else {
                        Button("Sync Now") { Task { await sync.sync() } }.disabled(sync.state == .syncing)
                    }
                    Spacer()
                    Button("Stop Syncing") { sync.signOut() }
                }
            }
        }
    }

    private var isProblem: Bool {
        switch sync.state {
        case .needsSignIn, .failed: true
        default: false
        }
    }

    private var status: String {
        switch sync.state {
        case .syncing: return "Syncing…"
        case .needsSignIn: return "Google signed you out"
        case .failed(let message): return "Last sync failed: \(message)"
        default:
            guard let last = sync.lastSync else { return "On" }
            return Date.now.timeIntervalSince(last) < 60 ? "Synced just now" : "Synced \(last.formatted(.relative(presentation: .named)))"
        }
    }
}
