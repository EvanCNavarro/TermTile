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
        // Functional core (ADR-0001): pure layout math + domain types. CoreGraphics only —
        // NO AppKit / ApplicationServices (enforced by .engine/checks/core-purity.sh).
        .target(name: "TermTileCore"),
        // The window-system port + AX adapters (ADR-0001). Depends on Core.
        .target(name: "TermTileKit", dependencies: ["TermTileCore"]),
        // Thin shell: MenuBarExtra UI + composition root. Depends on Kit and Core.
        .executableTarget(name: "TermTile", dependencies: ["TermTileKit", "TermTileCore"]),
        .testTarget(name: "TermTileCoreTests", dependencies: ["TermTileCore"]),
        .testTarget(name: "TermTileKitTests", dependencies: ["TermTileKit"])
    ]
)
