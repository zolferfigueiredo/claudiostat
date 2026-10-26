// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudioStat",
    platforms: [.macOS(.v15)],
    targets: [
        // The app's strings and languages, shared with the widget. They stay in the app's folder.
        .target(name: "ClaudioStatStrings", path: "Sources/ClaudioStat/Strings"),
        .executableTarget(name: "ClaudioStat", dependencies: ["ClaudioStatStrings"], exclude: ["Strings"],
                          swiftSettings: [.defaultIsolation(MainActor.self)]),
        // The desktop widget, in Swift 5 mode; build.sh and run.sh bundle it into the app (widget.sh).
        // It starts where Xcode starts an extension: from main, the widget crashes before it reaches the gallery.
        .executableTarget(name: "ClaudioStatWidget", dependencies: ["ClaudioStatStrings"], exclude: ["Info.plist", "Widget.entitlements"],
                          swiftSettings: [.swiftLanguageMode(.v5)],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        // Writes the strings into the widget for build.sh and run.sh (widget.sh): macOS reads Edit Widget's names from there.
        .executableTarget(name: "WidgetStrings", dependencies: ["ClaudioStatStrings"]),
        .testTarget(name: "ClaudioStatTests", dependencies: ["ClaudioStat", "ClaudioStatStrings"]),
    ]
)
