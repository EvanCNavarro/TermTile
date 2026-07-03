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
    private let appInfo: AppInfo

    init() {
        let isSelftest = ProcessInfo.processInfo.environment["TERMTILE_SELFTEST"] != nil
        // Selftest writes to a dedicated suite so it never pollutes the user's real defaults.
        let suiteName: String? = isSelftest ? Self.selftestSuite : nil

        let gap: CGFloat = 8
        let eps: CGFloat = 2
        let visibleFrame = Self.originAXVisibleFrame()

        // Construct the shared persistence + login-item ONCE so the Uninstaller acts on the SAME
        // instances the VM uses (it must deregister the real login item + purge the real defaults).
        let settings = UserDefaultsSettingsStore(suiteName: suiteName)
        let loginItem = SMAppServiceLoginItem()
        // The real ~/Library (non-sandboxed → the user's real home; TermTile can't be sandboxed).
        let library = (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        // NEVER arm the real uninstaller in a debug run (selftest/gallery) — a dev clicking Uninstall
        // in the interactive gallery would trash the user's REAL prefs/caches + the bundle. The VM
        // treats a nil uninstaller as a safe no-op; the button still renders for gallery validation.
        let isGallery = ProcessInfo.processInfo.environment["TERMTILE_GALLERY"] != nil
        let uninstaller: Uninstaller? = (isSelftest || isGallery) ? nil
            : Uninstaller(ownedPaths: OwnedPaths(library: library), loginItem: loginItem,
                          settings: settings, bundleURL: Bundle.main.bundleURL)

        appInfo = AppInfo.fromBundle()
        viewModel = MenuBarViewModel(
            settings: settings,
            loginItem: loginItem,
            appsProvider: WorkspaceTargetAppsProvider(),
            isTrustedProbe: MenuBarViewModel.liveTrustProbe,
            visibleFrame: visibleFrame,
            gap: gap,
            epsilon: eps,
            makeActor: { bundleID in
                TilingActor(system: AXWindowSystem(bundleID: bundleID), config: .disabled, epsilon: eps)
            },
            uninstaller: uninstaller)

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

        if isGallery {
            Self.showGallery(MenuBarContent(viewModel: viewModel, updater: updater, appInfo: appInfo))
        }
    }

    /// DEBUG gallery hook (RememBar's REMEMBAR_GALLERY pattern): show the REAL MenuBarContent panel in
    /// a normal window (interactive controls draw faithfully, unlike an offscreen ImageRenderer) — the
    /// FL-9 rendered-reality check for the About/Uninstall UI on a native app (no Chrome DevTools).
    /// LSUIElement apps have no windows, so flip to `.regular`.
    private static func showGallery(_ content: MenuBarContent) {
        Task { @MainActor in
            NSApplication.shared.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 460),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false   // programmatic NSWindow defaults true → ARC double-free
            window.title = "TermTile — panel (gallery)"
            window.contentView = NSHostingView(rootView: content)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            FileHandle.standardError.write(Data("GALLERY shown\n".utf8))
        }
    }

    var body: some Scene {
        MenuBarExtra(AppIdentity.appName) {
            MenuBarContent(viewModel: viewModel, updater: updater, appInfo: appInfo)
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
