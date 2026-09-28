// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Claudiostat",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Claudiostat", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "ClaudiostatTests", dependencies: ["Claudiostat"]),
    ]
)
