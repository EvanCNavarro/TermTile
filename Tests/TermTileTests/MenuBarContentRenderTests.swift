import AppKit
import CoreGraphics
import MacFaceKit
import SwiftUI
@testable import TermTile
import Testing
import TermTileCore
import TermTileKit

@MainActor
@Suite("MenuBarContent render")
struct MenuBarContentRenderTests {
    @Test("update availability changes the rendered overflow indicator without resizing")
    func updateAvailabilityChangesRenderedOverflowIndicatorWithoutResizing() throws {
        let plain = try renderedBitmap(availableUpdate: false)
        let available = try renderedBitmap(availableUpdate: true)

        #expect(plain.pixelsWide == available.pixelsWide)
        #expect(plain.pixelsHigh == available.pixelsHigh)
        #expect(changedPixels(between: plain, and: available) > 0)
    }

    private func renderedBitmap(availableUpdate: Bool) throws -> NSBitmapImageRep {
        let updater = Updater(startSession: { _ in nil })
        if availableUpdate {
            updater.recordAvailableUpdate(version: "9.9.9")
        }
        let view = MenuBarContent(
            viewModel: Self.viewModel(),
            updater: updater,
            appInfo: AppInfo(version: "0.2.6", build: "999")
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff))
    }

    private static func viewModel() -> MenuBarViewModel {
        let system = RenderWindowSystem()
        return MenuBarViewModel(
            settings: RenderSettingsStore(),
            loginItem: RenderLoginItem(),
            appsProvider: RenderAppsProvider(),
            isTrustedProbe: { true },
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            epsilon: 2,
            makeActor: { _ in TilingActor(system: system) }
        )
    }

    private func changedPixels(between lhs: NSBitmapImageRep, and rhs: NSBitmapImageRep) -> Int {
        var changed = 0
        for x in 0..<min(lhs.pixelsWide, rhs.pixelsWide) {
            for y in 0..<min(lhs.pixelsHigh, rhs.pixelsHigh) {
                if lhs.colorAt(x: x, y: y) != rhs.colorAt(x: x, y: y) {
                    changed += 1
                }
            }
        }
        return changed
    }
}

private final class RenderSettingsStore: SettingsStore, @unchecked Sendable {
    private var settings = AppSettings.defaults

    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
    func purge() { settings = .defaults }
}

private struct RenderLoginItem: LoginItem {
    var status: LoginItemStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

private struct RenderAppsProvider: TargetAppsProviding {
    func runningTargetApps() -> [TargetApp] {
        [TargetApp(bundleID: AppSettings.defaults.targetBundleID, name: "iTerm2")]
    }
}

private actor RenderWindowSystem: WindowSystem {
    func tileableWindows() -> [TrackedWindow] { [] }
    func writeFrame(_ id: CGWindowID, to target: CGRect) -> Bool { true }
}
