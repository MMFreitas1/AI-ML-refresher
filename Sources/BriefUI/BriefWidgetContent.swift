import BriefCore
import SwiftUI

/// The widget's layout. It lives here rather than in the widget target so it can also be
/// rendered off-screen for previews; the widget passes in its interactive save button.
public struct BriefWidgetContent<SaveButton: View>: View {
    let day: String?
    let items: [BriefItem]
    let savedIDs: Set<String>
    let isLarge: Bool
    /// Off-screen previews can't render `Link`, so they draw the same content without it.
    let linksEnabled: Bool
    let saveButton: (BriefItem, Bool) -> SaveButton

    public init(day: String?, items: [BriefItem], savedIDs: Set<String>, isLarge: Bool, linksEnabled: Bool = true,
                @ViewBuilder saveButton: @escaping (_ item: BriefItem, _ isSaved: Bool) -> SaveButton) {
        self.day = day
        self.items = items
        self.savedIDs = savedIDs
        self.isLarge = isLarge
        self.linksEnabled = linksEnabled
        self.saveButton = saveButton
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 4) {
            header
            if items.isEmpty {
                Spacer()
                Text("Open \(AppBrand.displayName) to fetch today's items.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    row(i + 1, item)
                    if isLarge && i < items.count - 1 { Divider() }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                AppBrand.widgetBadge(large: isLarge)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Top 5 today")
                .font(.caption.weight(.semibold))
            if let day {
                Text(day).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            // Opens the two-pane window (today ⇄ collection).
            link(URL(string: "aimlrefresher://open")!) {
                Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
    }

    private func row(_ rank: Int, _ item: BriefItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 12)
            link(item.url) {
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
            saveButton(item, savedIDs.contains(item.id))
        }
    }

    @ViewBuilder
    private func link(_ url: URL, @ViewBuilder label: () -> some View) -> some View {
        if linksEnabled { Link(destination: url, label: label) } else { label() }
    }
}
