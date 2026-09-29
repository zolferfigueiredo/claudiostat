// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudioStat",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ClaudioStat", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "ClaudioStatTests", dependencies: ["ClaudioStat"]),
    ]
)
