import AppKit
import BriefCore
import BriefUI
import SwiftUI

// Usage:
//   app-assets icon <AppIcon.appiconset dir>   render the macOS app icon set (run by build-release.sh)
//   app-assets preview <dir>                   render widget, icon and intro previews to check the look
//
// Both use AppBrand: the private brand when Brand/ is present, the neutral look otherwise.

@MainActor
func png(_ view: some View, size: CGSize, scheme: ColorScheme = .light, to url: URL) throws {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// macOS icon grid: the tile is 824/1024 of the canvas, centered, so the system shape lines up.
struct MacIcon: View {
    var body: some View {
        GeometryReader { g in
            AppBrand.appIcon()
                .frame(width: g.size.width * 824 / 1024, height: g.size.height * 824 / 1024)
                .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }
}

@MainActor
func renderIcon(into dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = points * scale
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try png(MacIcon(), size: CGSize(width: px, height: px), to: dir.appendingPathComponent(name))
            images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "app-assets"]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: dir.appendingPathComponent("Contents.json"))
}

@MainActor
func renderPreviews(into dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let items = Array((BriefStore().latestBrief()?.items ?? []).prefix(5))
    let saved: Set<String> = items.first.map { [$0.id] } ?? []

    for (scheme, name, bg) in [(ColorScheme.light, "light", Color(white: 0.93)), (.dark, "dark", Color(white: 0.17))] {
        for (large, size) in [(false, CGSize(width: 364, height: 170)), (true, CGSize(width: 364, height: 382))] {
            let widget = BriefWidgetContent(day: "2026-10-21", items: items, savedIDs: saved, isLarge: large, linksEnabled: false) { _, isSaved in
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark").font(.caption)
            }
            .padding(16)
            .background(bg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            try png(widget, size: size, scheme: scheme,
                    to: dir.appendingPathComponent("widget-\(large ? "large" : "medium")-\(name).png"))
        }

        for t in [0.2, 0.8, 2.0, 2.4, 4.0, 5.95, 7.0] {
            guard let frame = AppBrand.introFrame(at: t) else { break }
            try png(frame, size: CGSize(width: 1100, height: 700), scheme: scheme,
                    to: dir.appendingPathComponent(String(format: "intro-%@-t%04.1f.png", name, t)))
        }
    }
    try png(MacIcon(), size: CGSize(width: 512, height: 512), to: dir.appendingPathComponent("app-icon.png"))
    try png(HStack(spacing: 24) { ForEach([128, 64, 32], id: \.self) { MacIcon().frame(width: CGFloat($0), height: CGFloat($0)) } }
                .padding(20).background(Color(white: 0.9)),
            size: CGSize(width: 312, height: 168), to: dir.appendingPathComponent("app-icon-sizes.png"))
}

let args = CommandLine.arguments.dropFirst()
guard args.count == 2, let dir = args.last.map({ URL(fileURLWithPath: $0) }) else {
    print("usage: app-assets icon|preview <dir>")
    exit(2)
}
MainActor.assumeIsolated {
    do {
        switch args.first {
        case "icon": try renderIcon(into: dir)
        case "preview": try renderPreviews(into: dir)
        default: print("usage: app-assets icon|preview <dir>"); exit(2)
        }
        print("Wrote \(dir.path)")
    } catch {
        print("error: \(error)")
        exit(1)
    }
}
