import CryptoKit
import Foundation

/// Google sign-in for desktop apps ("OAuth 2.0 for installed apps"): the browser shows Google's
/// sign-in and consent, then sends the browser back to a 127.0.0.1 port the app listens on, with a
/// code the app exchanges for tokens. PKCE ties the code to this app instance.
/// Same flow in the Windows app. The Android app uses Google Play services instead.
public struct GoogleOAuth: Sendable {
    public let clientID: String
    /// For installed apps Google doesn't treat this as confidential, but it's required.
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public struct Tokens: Sendable {
        public let accessToken: String
        public let expiresAt: Date
        /// Only on the first sign-in; keep it (in the keychain) to get new access tokens.
        public let refreshToken: String?
    }

    /// One sign-in attempt: open `authorizationURL` in the browser, then `exchange` the code.
    public struct Attempt: Sendable {
        public let authorizationURL: URL
        public let redirectURI: String
        let verifier: String
        public let state: String
    }

    public func begin(redirectURI: String, scope: String) -> Attempt {
        let verifier = Self.randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomURLSafe(16)
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // A refresh token, so the app stays signed in.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return Attempt(authorizationURL: c.url!, redirectURI: redirectURI, verifier: verifier, state: state)
    }

    public func exchange(code: String, for attempt: Attempt) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "code_verifier": attempt.verifier,
            "redirect_uri": attempt.redirectURI,
        ])
    }

    /// A new access token. Throws `DriveAuthError` when Google no longer accepts the refresh token
    /// (signed out, password changed, access removed): the user has to sign in again.
    public func refresh(_ refreshToken: String) async throws -> Tokens {
        try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    /// Best effort: tells Google to forget this app's access.
    public static func revoke(_ token: String) async {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(form(["token": token]).utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> Tokens {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(Self.form(fields.merging(["client_id": clientID, "client_secret": clientSecret]) { a, _ in a }).utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        struct Reply: Decodable {
            let access_token: String?
            let expires_in: Double?
            let refresh_token: String?
            let error: String?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        if reply.error == "invalid_grant" { throw DriveAuthError() }
        guard let token = reply.access_token, (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FetchError.parse("Google's sign-in reply (\(reply.error ?? "no token"))")
        }
        // Renew a minute early.
        return Tokens(accessToken: token, expiresAt: Date().addingTimeInterval((reply.expires_in ?? 3600) - 60),
                      refreshToken: reply.refresh_token)
    }

    static func form(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
