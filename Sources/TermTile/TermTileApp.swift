import AppKit
import SwiftUI
import TermTileCore
import TermTileKit

/// The composition root (ADR-0001: the imperative shell wires the concrete adapters behind the
/// ports). A `MenuBarExtra(.window)` whose content is `MenuBarContent` over a `MenuBarViewModel`
/// built from the production `UserDefaultsSettingsStore` / `SMAppServiceLoginItem` /
/// `WorkspaceTargetAppsProvider` / live trust probe / `AXWindowSystem`-backed `TilingActor`.
///
/// `init()` is the reliable delegate hook (the SwiftUI adaptor never calls
/// `applicationDidFinishLaunching` — RememBar template), so the accessory-policy set and the
/// selftest dispatch both live here.
@main
struct TermTileApp: App {
    @NSApplicationDelegateAdaptor(TermTileAppDelegate.self) private var appDelegate
    private let viewModel: MenuBarViewModel
    private let updater = Updater()

    init() {
        let isSelftest = ProcessInfo.processInfo.environment["TERMTILE_SELFTEST"] != nil
        // Selftest writes to a dedicated suite so it never pollutes the user's real defaults.
        let suiteName: String? = isSelftest ? Self.selftestSuite : nil

        let gap: CGFloat = 8
        let eps: CGFloat = 2
        let visibleFrame = Self.originAXVisibleFrame()

        viewModel = MenuBarViewModel(
            settings: UserDefaultsSettingsStore(suiteName: suiteName),
            loginItem: SMAppServiceLoginItem(),
            appsProvider: WorkspaceTargetAppsProvider(),
            isTrustedProbe: MenuBarViewModel.liveTrustProbe,
            visibleFrame: visibleFrame,
            gap: gap,
            epsilon: eps,
            makeActor: { bundleID in
                TilingActor(system: AXWindowSystem(bundleID: bundleID), config: .disabled, epsilon: eps)
            })

        // Menu-bar utility: no dock icon, never takes window focus. Set here (init is reliable);
        // the delegate re-asserts it as a belt.
        NSApplication.shared.setActivationPolicy(.accessory)

        if isSelftest { Self.runSelftest(viewModel: viewModel) }

        // One-shot demo/E2E hook: TERMTILE_TILE_ONCE=1 fires the same rearrangeNow() the panel's
        // button invokes, against the persisted target, on the live run loop. No settings change.
        if ProcessInfo.processInfo.environment["TERMTILE_TILE_ONCE"] != nil {
            let vm = viewModel
            Task { @MainActor in
                await vm.rearrangeNow()
                FileHandle.standardError.write(Data("TILE_ONCE done\n".utf8))
            }
        }
    }

    var body: some Scene {
        MenuBarExtra(AppIdentity.appName) {
            MenuBarContent(viewModel: viewModel, updater: updater)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Composition helpers

    /// The origin screen's AX-space visible frame (the recipe proven in AXProbe/main.swift:442-444,
    /// #19a): read `NSScreen` on the main-actor init, use `.screens.first` (ORIGIN screen, never
    /// `.main`), flip Cocoa→AX top-left via `AXGeometry`. The value's correctness against a live
    /// tile is #14's proof; #12c's selftest targets a non-running app so it is never exercised here.
    private static func originAXVisibleFrame() -> CGRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        return AXGeometry.axFrame(fromCocoa: screen.visibleFrame, displayHeight: screen.frame.height)
    }

    private static let selftestSuite = "dev.ecn.apps.termtile.selftest"

    /// Env-gated live wiring PROVE (`TERMTILE_SELFTEST=1`), analogous to RememBar's `REMEMBAR_*`
    /// dev hooks. Runs on the LIVE NSApp run loop — NO `sem.wait`/blocking (TRAP-14; the deadlock
    /// there is sync-`main.swift`-specific, this loop is pumped). Proves the composition + the real
    /// target→persist wire executes in-process: a dedicated suite's target is changed and read back
    /// cross-instance (a real delta, not a stale rubber-stamp — R5/TRAP-15). Targets a NON-running
    /// bundle so `rearrangeNow` is inert and ZERO real windows move. NOT proven here: the SwiftUI
    /// button→VM binding (code-review-only residual).
    private static func runSelftest(viewModel: MenuBarViewModel) {
        // Markers go to UNBUFFERED stderr (TRAP-14: print() to a pipe/file is block-buffered and
        // is lost on SIGTERM — the first live-prove run captured nothing this way). The "start"
        // mark is synchronous in init (proves the hook is reached even before the run loop); the
        // MainActor Task runs once NSApp's main executor starts.
        func mark(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
        let store = UserDefaultsSettingsStore(suiteName: selftestSuite)
        let pid = ProcessInfo.processInfo.processIdentifier
        mark("SELFTEST start pid=\(pid) pre target=\(store.load().targetBundleID)")
        Task { @MainActor in
            await viewModel.setTarget("dev.ecn.apps.termtile.selftest-none")  // non-running → inert
            await viewModel.rearrangeNow()                                     // the real button wire
            let post = UserDefaultsSettingsStore(suiteName: selftestSuite).load()
            mark("SELFTEST persisted target=\(post.targetBundleID)")
            mark("SELFTEST done")
        }
    }
}

/// Minimal app delegate — the reliable place for lifecycle hooks the SwiftUI adaptor omits.
/// Re-asserts the accessory activation policy (belt to `init()`'s set).
final class TermTileAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
