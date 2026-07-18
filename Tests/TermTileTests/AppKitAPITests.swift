import Foundation
import Testing

@Suite("TermTile AppKit API use")
struct AppKitAPITests {
    private static func repoRoot() -> URL {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate Package.swift above \(#filePath)")
    }

    @Test("app-owned activation avoids deprecated ignoringOtherApps")
    func appOwnedActivationAvoidsIgnoringOtherApps() {
        let root = Self.repoRoot()
        let appSources = [
            "Sources/TermTile/MenuBarContent.swift",
            "Sources/TermTile/TermTileApp.swift"
        ]
        let combined = appSources
            .map { root.appending(path: $0) }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        #expect(!combined.contains("activate(ignoringOtherApps:"),
                "app-owned windows should use NSApplication.activate(), not deprecated ignoringOtherApps")
        #expect(combined.contains("NSApplication.shared.activate()"),
                "the app-owned activation path should use the non-deprecated AppKit API")
    }

    @Test("tiling and foregrounding share target-app resolution")
    func tilingAndForegroundingShareTargetAppResolution() {
        let root = Self.repoRoot()
        let ax = (try? String(contentsOf: root.appending(path: "Sources/TermTileKit/AXWindowSystem.swift"),
                              encoding: .utf8)) ?? ""
        let foreground = (try? String(contentsOf:
            root.appending(path: "Sources/TermTileKit/WorkspaceTargetAppForegrounder.swift"),
            encoding: .utf8)) ?? ""

        #expect(ax.contains("TargetRunningApplicationResolver.preferred"),
                "AX tiling must resolve the selected app through the shared target-app authority")
        #expect(foreground.contains("TargetRunningApplicationResolver.preferred"),
                "foregrounding must resolve the selected app through the shared target-app authority")
        #expect(!foreground.contains("private static func targetApp(for:"),
                "foregrounding must not keep a second target-app resolver")
    }

    @Test("update dialog uses the shared app identity authority")
    func updateDialogUsesSharedAppIdentity() {
        let root = Self.repoRoot()
        let source = (try? String(contentsOf: root.appending(path: "Sources/TermTile/TermTileUserDriver.swift"),
                                  encoding: .utf8)) ?? ""

        #expect(source.contains("UpdateWindowController(appName: AppIdentity.appName"),
                "the MacFaceKit update adapter should read TermTile's name from AppIdentity")
        #expect(!source.contains("appName: \"TermTile\""),
                "the MacFaceKit update adapter must not duplicate TermTile's app-name literal")
    }
}
