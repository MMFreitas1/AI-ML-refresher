// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIBrief",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BriefCore", targets: ["BriefCore"]),
        .executable(name: "AIBrief", targets: ["BriefApp"]),
        .executable(name: "brief-cli", targets: ["brief-cli"]),
    ],
    targets: [
        .target(name: "BriefCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "BriefApp", dependencies: ["BriefCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "brief-cli", dependencies: ["BriefCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "BriefCoreTests", dependencies: ["BriefCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
