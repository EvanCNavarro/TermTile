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
    dependencies: [
        // Shared 400faces macOS design system (tokens + components) — public + tagged, resolvable from
        // any clone / CI without a local checkout.
        .package(url: "https://github.com/400faces/MacFaceKit.git", from: "0.1.0")
    ],
    targets: [
        // Functional core (ADR-0001): pure layout math + domain types. CoreGraphics only —
        // NO AppKit / ApplicationServices (enforced by .engine/checks/core-purity.sh).
        .target(name: "TermTileCore"),
        // The window-system port + AX adapters (ADR-0001). Depends on Core.
        .target(name: "TermTileKit", dependencies: ["TermTileCore"]),
        // Thin shell: MenuBarExtra UI + composition root. Depends on Kit and Core, plus Sparkle
        // for auto-updates. The runtime rpath lets the bundled binary find Sparkle.framework that
        // build-app.sh embeds in Contents/Frameworks — linking Sparkle WITHOUT this + the embed =
        // dyld crash (RememBar-audit §1).
        .executableTarget(
            name: "TermTile",
            dependencies: ["TermTileKit", "TermTileCore", "Sparkle",
                           .product(name: "MacFaceKit", package: "MacFaceKit")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]),
        // Local binaryTarget (SPM's remote artifact downloader hangs in some sandboxes). The
        // xcframework is gitignored + vendored by scripts/fetch-sparkle.sh — run it once after clone.
        .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"),
        .testTarget(name: "TermTileCoreTests", dependencies: ["TermTileCore"]),
        .testTarget(name: "TermTileKitTests", dependencies: ["TermTileKit"])
    ]
)
