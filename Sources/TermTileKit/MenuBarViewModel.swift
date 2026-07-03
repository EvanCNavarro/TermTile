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
    /// Whether Accessibility (TCC) trust is granted — gates the permission fix-it row.
    public private(set) var isAccessibilityTrusted: Bool
    /// Whether the app is registered to launch at login (source of truth = `LoginItem.status`).
    public private(set) var launchAtLogin: Bool

    // Injected seams (untracked — not observable UI state). `settings` is internal so the
    // @testable suite can assert persistence; the executable never reads it directly.
    let settings: any SettingsStore
    @ObservationIgnored private let loginItem: any LoginItem
    @ObservationIgnored private let isTrustedProbe: @Sendable () -> Bool
    @ObservationIgnored private let visibleFrame: CGRect
    @ObservationIgnored private let gap: CGFloat
    @ObservationIgnored private let epsilon: CGFloat
    @ObservationIgnored private let makeActor: @Sendable (String) -> TilingActor
    @ObservationIgnored private var actor: TilingActor

    public init(
        settings: any SettingsStore,
        loginItem: any LoginItem,
        appsProvider: any TargetAppsProviding,
        isTrustedProbe: @escaping @Sendable () -> Bool,
        visibleFrame: CGRect,
        gap: CGFloat,
        epsilon: CGFloat,
        makeActor: @escaping @Sendable (String) -> TilingActor
    ) {
        let loaded = settings.load()
        self.settings = settings
        self.loginItem = loginItem
        self.isTrustedProbe = isTrustedProbe
        self.visibleFrame = visibleFrame
        self.gap = gap
        self.epsilon = epsilon
        self.makeActor = makeActor
        self.targetBundleID = loaded.targetBundleID
        self.availableApps = appsProvider.runningTargetApps()
        self.isAccessibilityTrusted = isTrustedProbe()
        self.launchAtLogin = loginItem.status == .enabled
        self.actor = makeActor(loaded.targetBundleID)
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

    /// Re-read the trust probe — called when the menu re-opens, so the fix-it row disappears once
    /// the user grants Accessibility in System Settings.
    public func refreshTrust() {
        isAccessibilityTrusted = isTrustedProbe()
    }

    /// "Rearrange now": tile the target app's windows onto the grid immediately — the one verb
    /// the app does. Re-probes trust first so the fix-it row never shows stale (a grant made while
    /// the panel's view stayed alive was rendering as still-required).
    public func rearrangeNow() async {
        refreshTrust()
        await actor.activate(config: TileConfig(isEnabled: true, visibleFrame: visibleFrame, gap: gap))
    }

    private func persist() {
        settings.save(AppSettings(targetBundleID: targetBundleID))
    }

    /// The PRODUCTION Accessibility-trust probe for the composition root to inject. Defined in Kit
    /// so it can close over the Kit-internal `AccessibilityTrust` (the executable never sees that
    /// type). `prompting: false` — a read-only status check that never pops the grant dialog on a
    /// menu open (the user reaches System Settings via the fix-it row's `Link` instead).
    public static let liveTrustProbe: @Sendable () -> Bool = {
        AccessibilityTrust.isTrusted(prompting: false)
    }
}
