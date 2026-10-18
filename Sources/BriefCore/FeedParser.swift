import Foundation

/// Minimal RSS 2.0 / Atom parser: title, link, summary and date per entry.
public struct FeedEntry: Sendable {
    public var title = ""
    public var link = ""
    public var summary = ""
    public var date: Date?
}

final class FeedParser: NSObject, XMLParserDelegate {
    private var entries: [FeedEntry] = []
    private var current: FeedEntry?
    private var text = ""
    private var dateText = ""

    static func parse(_ data: Data) throws -> [FeedEntry] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || !delegate.entries.isEmpty else {
            throw FetchError.parse("feed: \(parser.parserError?.localizedDescription ?? "unknown error")")
        }
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "item", "entry":
            current = FeedEntry()
            dateText = ""
        case "link" where current != nil:
            // Atom: <link rel="alternate" href="…"/>. Prefer the alternate link over others.
            if let href = attributes["href"], attributes["rel"] ?? "alternate" == "alternate" {
                current?.link = href
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        let value = text.trimmed
        switch name {
        case "title": current?.title = Format.stripHTML(value)
        case "link" where !value.isEmpty: current?.link = value
        case "description", "summary":
            current?.summary = Format.stripHTML(value)
        case "content", "content:encoded":
            if current?.summary.isEmpty ?? false { current?.summary = Format.stripHTML(value) }
        case "pubDate", "published", "updated", "dc:date":
            if dateText.isEmpty || name == "published" { dateText = value }
        case "item", "entry":
            if var entry = current {
                entry.date = Self.date(dateText)
                if !entry.link.isEmpty { entries.append(entry) }
            }
            current = nil
        default: break
        }
        text = ""
    }

    private static func date(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        if let d = ISO8601.parse(s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
