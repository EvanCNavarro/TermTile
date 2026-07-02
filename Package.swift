// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TermTile",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TermTile", targets: ["TermTile"])
    ],
    targets: [
        .executableTarget(name: "TermTile"),
        .testTarget(name: "TermTileTests", dependencies: ["TermTile"])
    ]
)
