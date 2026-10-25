// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudioStat",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ClaudioStat", swiftSettings: [.defaultIsolation(MainActor.self)]),
        // The desktop widget, the phone app's widget code (Swift 5 there); build.sh and run.sh bundle it into the app.
        // It starts where Xcode starts an extension: from main, the widget crashes before it reaches the gallery.
        .executableTarget(name: "ClaudioStatWidget", exclude: ["Info.plist", "Widget.entitlements", "Localizable.xcstrings"],
                          swiftSettings: [.swiftLanguageMode(.v5)],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .testTarget(name: "ClaudioStatTests", dependencies: ["ClaudioStat"]),
    ]
)
