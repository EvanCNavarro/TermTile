// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TermTile",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TermTile", targets: ["TermTile"]),
        .executable(name: "AXProbe", targets: ["AXProbe"])
    ],
    targets: [
        .executableTarget(name: "TermTile"),
        // Spike 02 probe (throwaway-quality, committed): observes TCC trust attribution.
        .executableTarget(name: "AXProbe"),
        .testTarget(name: "TermTileTests", dependencies: ["TermTile"])
    ]
)
