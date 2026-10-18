import Foundation

public struct HTTP: Sendable {
    public var session: URLSession
    public var userAgent = "AIBrief/1.0 (macOS; personal daily reading widget)"
    /// Optional, raises GitHub's search rate limit. Read from the `GITHUB_TOKEN` environment variable.
    public var githubToken: String? = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]

    public init(session: URLSession = .shared) { self.session = session }

    public func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.status(http.statusCode, url.host ?? url.absoluteString)
        }
        return data
    }

    public func json<T: Decodable>(_ type: T.Type, from url: URL, headers: [String: String] = [:]) async throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ISO8601.parse(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Bad date \(s)"))
            }
            return date
        }
        return try decoder.decode(T.self, from: try await data(url, headers: headers))
    }
}

public enum FetchError: LocalizedError {
    case status(Int, String)
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case let .status(code, host): code == 429 ? "\(host) rate-limited the request (HTTP 429)" : "\(host) returned HTTP \(code)"
        case let .parse(what): "Could not parse \(what)"
        }
    }
}

enum ISO8601 {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

enum Format {
    /// 12345 → "12.3k"
    static func compact(_ n: Double) -> String {
        switch n {
        case 1_000_000...: String(format: "%.1fM", n / 1_000_000)
        case 10_000...: String(format: "%.0fk", n / 1_000)
        case 1_000...: String(format: "%.1fk", n / 1_000)
        default: String(Int(n))
        }
    }

    static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                               ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " "), ("&#32;", " ")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
    }

    static func truncate(_ s: String, _ n: Int = 240) -> String {
        s.count <= n ? s : String(s.prefix(n)).trimmed + "…"
    }
}
