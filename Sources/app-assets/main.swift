import AppKit
import BriefCore
import BriefUI
import SwiftUI

// Usage:
//   app-assets icon <AppIcon.appiconset dir>   render the macOS app icon set (run by build-release.sh)
//   app-assets preview <dir>                   render widget, icon and intro previews to check the look
//   app-assets ico <file.ico> [--neutral]      render the Windows icon (.ico, plus a 256px .png beside it)
//
// All use AppBrand: the private brand when Brand/ is present, the neutral look otherwise
// (or with --neutral, for the icon committed in windows/).

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

/// Neutral Windows icon. Drawn from plain shapes: SF Symbols may only ship on Apple platforms.
struct NeutralWindowsIcon: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                // A stack of three cards, front one brightest.
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                        .fill(Color.white.opacity([0.35, 0.6, 1.0][i]))
                        .frame(width: s * (0.42 + 0.06 * Double(i)), height: s * 0.30)
                        .offset(y: s * (-0.12 + 0.09 * Double(i)))
                }
                Sparkle()
                    .fill(Color.white)
                    .frame(width: s * 0.22, height: s * 0.22)
                    .offset(x: s * 0.24, y: s * -0.25)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Four-pointed star.
struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), w = r.width / 2, k = w * 0.22
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + w), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - w), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
}

/// Windows .ico with PNG-compressed entries (supported since Windows Vista).
@MainActor
func renderICO(to file: URL, neutral: Bool) throws {
    let icon: AnyView = neutral || !AppBrand.isBranded ? AnyView(NeutralWindowsIcon()) : AnyView(AppBrand.appIcon())
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    var images: [Data] = []
    for px in sizes {
        let url = tmp.appendingPathComponent("\(px).png")
        try png(icon, size: CGSize(width: px, height: px), to: url)
        images.append(try Data(contentsOf: url))
    }
    var ico = Data()
    func u16(_ v: Int) { ico.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func u32(_ v: Int) { u16(v & 0xFFFF); u16(v >> 16) }
    u16(0); u16(1); u16(sizes.count)
    var offset = 6 + 16 * sizes.count
    for (px, data) in zip(sizes, images) {
        ico.append(UInt8(px >= 256 ? 0 : px)); ico.append(UInt8(px >= 256 ? 0 : px))
        ico.append(0); ico.append(0)
        u16(1); u16(32); u32(data.count); u32(offset)
        offset += data.count
    }
    images.forEach { ico.append($0) }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ico.write(to: file)
    try images.last!.write(to: file.deletingPathExtension().appendingPathExtension("png"))
}

let args = Array(CommandLine.arguments.dropFirst())
let usage = "usage: app-assets icon|preview <dir> | app-assets ico <file.ico> [--neutral]"
guard args.count >= 2, let dir = args.dropFirst().first.map({ URL(fileURLWithPath: $0) }) else {
    print(usage)
    exit(2)
}
MainActor.assumeIsolated {
    do {
        switch args.first {
        case "icon": try renderIcon(into: dir)
        case "preview": try renderPreviews(into: dir)
        case "ico": try renderICO(to: dir, neutral: args.contains("--neutral"))
        default: print(usage); exit(2)
        }
        print("Wrote \(dir.path)")
    } catch {
        print("error: \(error)")
        exit(1)
    }
}
