// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DeckCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DeckCore", targets: ["DeckCore"]),
        .executable(name: "deck-hook", targets: ["DeckHook"]),
    ],
    targets: [
        .target(name: "DeckCore"),
        .executableTarget(name: "DeckHook", dependencies: ["DeckCore"]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"]),
    ]
)
