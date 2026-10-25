// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudioStat",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ClaudioStat", swiftSettings: [.defaultIsolation(MainActor.self)]),
        // The desktop widget, the phone app's widget code (Swift 5 there); build.sh and run.sh bundle it into the app.
        .executableTarget(name: "ClaudioStatWidget", exclude: ["Info.plist", "Widget.entitlements", "Localizable.xcstrings"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ClaudioStatTests", dependencies: ["ClaudioStat"]),
    ]
)
