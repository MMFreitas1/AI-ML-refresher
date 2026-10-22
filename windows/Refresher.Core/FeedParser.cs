using System.Globalization;
using System.Text.RegularExpressions;
using System.Xml;

namespace Refresher.Core;

/// <summary>Minimal RSS 2.0 / Atom parser: title, link, summary and date per entry.</summary>
public sealed record FeedEntry(string Title, string Link, string Summary, DateTimeOffset? Date);

public static partial class FeedParser
{
    public static List<FeedEntry> Parse(byte[] data)
    {
        var entries = new List<FeedEntry>();
        var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null };
        string? title = null, link = null, summary = null, dateText = null;
        var inEntry = false;
        var text = new System.Text.StringBuilder();

        try
        {
            using var reader = XmlReader.Create(new MemoryStream(data), settings);
            while (reader.Read())
            {
                switch (reader.NodeType)
                {
                    case XmlNodeType.Element:
                        text.Clear();
                        var name = reader.Name;
                        if (name is "item" or "entry")
                        {
                            inEntry = true;
                            title = link = summary = dateText = null;
                        }
                        else if (name == "link" && inEntry)
                        {
                            // Atom: <link rel="alternate" href="…"/>. Prefer the alternate link over others.
                            var href = reader.GetAttribute("href");
                            if (href != null && (reader.GetAttribute("rel") ?? "alternate") == "alternate") link = href;
                        }
                        if (reader.IsEmptyElement) End(name);
                        break;
                    case XmlNodeType.Text or XmlNodeType.CDATA or XmlNodeType.SignificantWhitespace or XmlNodeType.Whitespace:
                        text.Append(reader.Value);
                        break;
                    case XmlNodeType.EndElement:
                        End(reader.Name);
                        break;
                }
            }
        }
        catch (XmlException e)
        {
            if (entries.Count == 0) throw FetchError.Parse($"feed: {e.Message}");
        }
        return entries;

        void End(string name)
        {
            if (!inEntry) { text.Clear(); return; }
            var value = text.ToString().Trim();
            switch (name)
            {
                case "title": title = Format.StripHTML(value); break;
                case "link" when value.Length > 0: link = value; break;
                case "description" or "summary": summary = Format.StripHTML(value); break;
                case "content" or "content:encoded":
                    if (string.IsNullOrEmpty(summary)) summary = Format.StripHTML(value);
                    break;
                case "pubDate" or "published" or "updated" or "dc:date":
                    if (string.IsNullOrEmpty(dateText) || name == "published") dateText = value;
                    break;
                case "item" or "entry":
                    if (!string.IsNullOrEmpty(link)) entries.Add(new FeedEntry(title ?? "", link, summary ?? "", ParseDate(dateText)));
                    inEntry = false;
                    break;
            }
            text.Clear();
        }
    }

    /// <summary>ISO 8601 (Atom) or RFC 822 (RSS), e.g. "Thu, 08 Oct 2026 11:26:09 GMT" or "… +0000".</summary>
    public static DateTimeOffset? ParseDate(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        s = s.Trim();
        if (char.IsDigit(s[0])) return Iso8601.Parse(s);
        // Normalize the zone to an offset .NET understands.
        var m = Rfc822Zone().Match(s);
        if (!m.Success) return null;
        var zone = m.Groups[2].Value;
        var offset = zone switch
        {
            "GMT" or "UT" or "UTC" or "Z" => "+00:00",
            "EST" => "-05:00", "EDT" => "-04:00", "CST" => "-06:00", "CDT" => "-05:00",
            "MST" => "-07:00", "MDT" => "-06:00", "PST" => "-08:00", "PDT" => "-07:00",
            _ when zone.Length == 5 => $"{zone[..3]}:{zone[3..]}",
            _ => null,
        };
        if (offset == null) return null;
        string[] formats = ["ddd, d MMM yyyy HH:mm:ss zzz", "ddd, d MMM yyyy HH:mm zzz", "d MMM yyyy HH:mm:ss zzz"];
        return DateTimeOffset.TryParseExact($"{m.Groups[1].Value} {offset}", formats, CultureInfo.InvariantCulture,
                                            DateTimeStyles.AllowWhiteSpaces, out var d) ? d : null;
    }

    [GeneratedRegex(@"^(.*\d)\s+([A-Z]{1,3}|[+-]\d{4})$")] private static partial Regex Rfc822Zone();
}
