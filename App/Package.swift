// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeDeck",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "DeckCore", path: ".."),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeDeck",
            dependencies: [
                .product(name: "DeckCore", package: "DeckCore"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
