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
        // Functional core (ADR-0001): pure layout math + domain types. CoreGraphics only —
        // NO AppKit / ApplicationServices (enforced by .engine/checks/core-purity.sh).
        .target(name: "TermTileCore"),
        // The window-system port + AX adapters (ADR-0001). Depends on Core.
        .target(name: "TermTileKit", dependencies: ["TermTileCore"]),
        // Thin shell: MenuBarExtra UI + composition root. Depends on Kit and Core.
        .executableTarget(name: "TermTile", dependencies: ["TermTileKit", "TermTileCore"]),
        // Spike 02-06 probe (throwaway-quality, committed): observes TCC trust, AX
        // enumeration/frame-writes/events, and drag-end/self-move tagging. Depends on the
        // PURE core so the spike-06 dragprobe exercises the REAL MoveClassifier (no
        // inline-copy drift); TermTileCore has no AppKit/AX so it cannot pollute the probe.
        // Also depends on Kit (#19a livecheck): the throwaway probe drives the REAL
        // AXWindowSystem adapter live against iTerm2, so the grid-snap PROVE exercises product
        // code, not an inline copy (same no-drift rationale as the Core dep).
        .executableTarget(name: "AXProbe", dependencies: ["TermTileCore", "TermTileKit"]),
        .testTarget(name: "TermTileCoreTests", dependencies: ["TermTileCore"]),
        .testTarget(name: "TermTileKitTests", dependencies: ["TermTileKit"])
    ]
)
