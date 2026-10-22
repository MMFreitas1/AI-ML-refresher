// swift-tools-version:6.0
import Foundation
import PackageDescription

// Official releases are built with a private brand kit cloned next to this repository, at
// ../brand-kit (not public; see BRAND.md). Without it, the app builds with a neutral look.
let brandPath = "../brand-kit/products/ai-ml-refresher"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasBrand = FileManager.default.fileExists(atPath: root.appendingPathComponent("\(brandPath)/Package.swift").path)

let package = Package(
    name: "Refresher",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BriefCore", targets: ["BriefCore"]),
        .library(name: "BriefUI", targets: ["BriefUI"]),
        .executable(name: "Refresher", targets: ["BriefApp"]),
        .executable(name: "brief-cli", targets: ["brief-cli"]),
    ],
    dependencies: hasBrand ? [.package(path: brandPath)] : [],
    targets: [
        .target(name: "BriefCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // Shared views for the app and widget, and the brand switch (AppBrand).
        .target(name: "BriefUI",
                dependencies: ["BriefCore"] + (hasBrand ? [.product(name: "PrivateBrand", package: "ai-ml-refresher")] : []),
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "BriefApp", dependencies: ["BriefCore", "BriefUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Renders the app icon and previews: `swift run app-assets icon|preview <dir>`.
        .executableTarget(name: "app-assets", dependencies: ["BriefCore", "BriefUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "brief-cli", dependencies: ["BriefCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "BriefCoreTests", dependencies: ["BriefCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
