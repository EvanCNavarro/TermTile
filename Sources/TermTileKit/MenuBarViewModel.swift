import CoreGraphics
import Foundation
import Observation
import TermTileCore

/// The menu-bar shell's presentation/composition logic (ADR-0001 imperative shell). It binds the
/// ports #12a/#12b/#19 built — `SettingsStore`, `LoginItem`, `TargetAppsProviding`, an injected
/// Accessibility-trust probe, and a `makeActor` factory — into the observable state the SwiftUI
/// `MenuBarExtra` renders and the actions its controls invoke. `@Observable` (the standalone
/// `Observation` module, macOS 14 — NOT SwiftUI, so Kit stays UI-free and unit-testable) drives
/// the view's reactivity; `@MainActor` because it is the UI's owner.
///
/// Deliberately does NOT start `TilingActor.run()`/live-event observation — that leak-prone path
/// (the module-global AXObserver bridge can't host two live adapters across a target-switch) is
/// #14's fresh-boot E2E surface. #12c drives only `activate()`: toggle-on tiles, toggle-off is
/// inert (`TileEngine.retileCommands`'s `isEnabled` guard), target-switch rebuilds the actor over
/// a fresh adapter for the NEXT activate. `visibleFrame` is INJECTED (never read from a live
/// `NSScreen` here) so the logic is deterministic under test; the composition root supplies the
/// real origin-screen AX frame.
@MainActor
@Observable
public final class MenuBarViewModel {
    /// The picker selection — the bundle id the AX adapter targets (spec-draft:18). Persisted.
    public private(set) var targetBundleID: String
    /// The apps the picker offers, snapshotted at init from the provider.
    public private(set) var availableApps: [TargetApp]
    /// Whether Accessibility (TCC) trust is granted — gates the "Rearrange now" button.
    public private(set) var isAccessibilityTrusted: Bool
    /// Whether the user has EVER granted Accessibility — a tracked mirror of the persisted flag,
    /// loaded once at init and latched by `syncTrust()`. Drives `accessibilityState`; read from here
    /// (not `settings.load()`) so Observation tracks it and the view recomputes on change (#23 S1).
    public private(set) var wasTrusted: Bool
    /// Whether the app is registered to launch at login (source of truth = `LoginItem.status`).
    public private(set) var launchAtLogin: Bool
    /// The tile gap in points (#17a) — loaded from settings, tracked so the Stepper live-updates.
    /// Was an injected `let`; now user-state like `targetBundleID`. Clamped by `setGap`.
    public private(set) var gap: CGFloat

    /// The fix-it row's state (#23): trusted → no row; never granted → first-grant prompt; untrusted
    /// but previously granted → the honest grant-BROKEN message (moved/duplicate bundle). Computed
    /// over the two tracked vars, so it's Observation-reactive.
    public var accessibilityState: AccessibilityState {
        if isAccessibilityTrusted { return .trusted }
        return wasTrusted ? .grantBroken : .needsFirstGrant
    }

    // Injected seams (untracked — not observable UI state). `settings` is internal so the
    // @testable suite can assert persistence; the executable never reads it directly.
    let settings: any SettingsStore
    @ObservationIgnored private let loginItem: any LoginItem
    @ObservationIgnored private let isTrustedProbe: @Sendable () -> Bool
    @ObservationIgnored private let visibleFrame: CGRect
    @ObservationIgnored private let epsilon: CGFloat
    @ObservationIgnored private let makeActor: @Sendable (String) -> TilingActor
    @ObservationIgnored private var actor: TilingActor
    /// The Uninstaller — injected by the composition root (which supplies the real library +
    /// bundle URL), so the VM never touches `FileManager`/`Bundle.main` and stays test-injected.
    /// Optional: unbundled/test contexts leave it nil (uninstall is a no-op there).
    @ObservationIgnored private let uninstaller: Uninstaller?

    public init(
        settings: any SettingsStore,
        loginItem: any LoginItem,
        appsProvider: any TargetAppsProviding,
        isTrustedProbe: @escaping @Sendable () -> Bool,
        visibleFrame: CGRect,
        epsilon: CGFloat,
        makeActor: @escaping @Sendable (String) -> TilingActor,
        uninstaller: Uninstaller? = nil
    ) {
        let loaded = settings.load()
        self.settings = settings
        self.loginItem = loginItem
        self.isTrustedProbe = isTrustedProbe
        self.visibleFrame = visibleFrame
        self.epsilon = epsilon
        self.makeActor = makeActor
        self.uninstaller = uninstaller
        self.targetBundleID = loaded.targetBundleID
        self.availableApps = appsProvider.runningTargetApps()
        self.isAccessibilityTrusted = false   // set by syncTrust() below (single source)
        self.wasTrusted = loaded.wasTrusted
        // #17a — user-state loaded like targetBundleID. Clamped on READ too: a tampered/downgraded
        // plist (gap=9999) would otherwise flow unclamped to TileLayout as a negative column width.
        self.gap = Self.clampedGap(CGFloat(loaded.gap))
        self.launchAtLogin = loginItem.status == .enabled
        self.actor = makeActor(loaded.targetBundleID)
        syncTrust()   // probe + latch at init — catches the trusted-at-launch / migrating case (#23 B2)
    }

    /// Re-read the trust probe and LATCH `wasTrusted` the first time trust is observed (guarded on
    /// the persisted flag, NOT a probe edge — so it fires for a user already trusted at launch, the
    /// common case #23 B2 exists for). Single source for `isAccessibilityTrusted` (init + refresh).
    private func syncTrust() {
        isAccessibilityTrusted = isTrustedProbe()
        if isAccessibilityTrusted && !wasTrusted {
            wasTrusted = true
            persist()
        }
    }

    /// Run the uninstall (About panel's Uninstall action). Returns the outcome for the UI to render
    /// (removed / partial failures / Finder-reveal / the TCC-reset guidance), or nil if no
    /// uninstaller was injected (unbundled). The caller quits with `exit(0)` after the user
    /// dismisses the outcome — NOT `NSApp.terminate` (which would re-flush the purged prefs domain).
    public func uninstall() -> Uninstaller.UninstallOutcome? {
        uninstaller?.uninstall()
    }

    /// The Privacy_Accessibility deep link the fix-it row opens (re-exported from the internal
    /// `AccessibilityTrust` so the executable's view needs no direct dependency on it).
    public var accessibilitySettingsURL: URL { AccessibilityTrust.settingsDeepLink }

    /// Change the target app. Persists `targetBundleID` and rebuilds the actor over a fresh adapter
    /// for the new target. Does NOT auto-tile — TermTile is a manual tool: the user picks the app,
    /// then presses "Rearrange now" when they want the grid.
    public func setTarget(_ bundleID: String) async {
        targetBundleID = bundleID
        persist()
        actor = makeActor(bundleID)
    }

    /// The allowed tile-gap range (#17a): 0 = flush, 40 = generous. Every N=1..12 column layout
    /// stays valid (positive widths) across this range on any real display (audited).
    public static let gapRange: ClosedRange<CGFloat> = 0...40

    /// The single clamp authority (#17a) — used on BOTH the write (`setGap`) and read (init from a
    /// persisted value) paths, so no gap outside `gapRange` can ever reach `TileLayout`.
    private static func clampedGap(_ points: CGFloat) -> CGFloat {
        min(max(points, gapRange.lowerBound), gapRange.upperBound)
    }

    /// Change the tile gap (#17a). Clamps to `gapRange` and persists. Manual model — like `setTarget`,
    /// it does NOT auto-tile; the new gap applies on the next "Rearrange now", avoiding an AX
    /// write-storm on every increment.
    public func setGap(_ points: CGFloat) {
        gap = Self.clampedGap(points)
        persist()
    }

    /// Register / unregister as a login item, then refresh `launchAtLogin` from the authoritative
    /// `LoginItem.status`. Errors are swallowed and reflected as the real post-call status (the
    /// unsigned-binary throw path is observed live in #13, not surfaced as UI here).
    public func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try loginItem.register() } else { try loginItem.unregister() }
        } catch {
            // Registration failed (e.g. unsigned binary) — fall through; status reflects reality.
        }
        launchAtLogin = loginItem.status == .enabled
    }

    /// Re-read the trust probe (and latch `wasTrusted`) — called when the menu re-opens, so the
    /// fix-it row disappears once the user grants Accessibility in System Settings.
    public func refreshTrust() {
        syncTrust()
    }

    /// "Rearrange now": tile the target app's windows onto the grid immediately — the one verb
    /// the app does. Re-probes trust first so the fix-it row never shows stale (a grant made while
    /// the panel's view stayed alive was rendering as still-required).
    public func rearrangeNow() async {
        refreshTrust()
        await actor.activate(config: TileConfig(isEnabled: true, visibleFrame: visibleFrame, gap: gap))
    }

    /// One persist for ALL writes — carries the live `wasTrusted` so an unrelated save (e.g. a
    /// target-app change) never clobbers the latch back to false (#23 B1).
    private func persist() {
        settings.save(AppSettings(targetBundleID: targetBundleID, wasTrusted: wasTrusted, gap: Double(gap)))
    }

    /// The PRODUCTION Accessibility-trust probe for the composition root to inject. Defined in Kit
    /// so it can close over the Kit-internal `AccessibilityTrust` (the executable never sees that
    /// type). `prompting: false` — a read-only status check that never pops the grant dialog on a
    /// menu open (the user reaches System Settings via the fix-it row's `Link` instead).
    public static let liveTrustProbe: @Sendable () -> Bool = {
        AccessibilityTrust.isTrusted(prompting: false)
    }
}
