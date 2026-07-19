import CoreGraphics
import Foundation
import Observation
import TermTileCore

/// Menu-bar presentation/composition logic (ADR-0001 imperative shell). It binds injected ports into
/// observable state for SwiftUI while keeping Kit UI-free and unit-testable.
/// This shell drives `activate()` only; live observation is a separate surface. `visibleFrame` is
/// injected so layout behavior stays deterministic under test.
@MainActor
@Observable
public final class MenuBarViewModel {
    /// The picker selection — the bundle id the AX adapter targets (spec-draft:18). Persisted.
    public private(set) var targetBundleID: String
    /// The apps the picker offers, snapshotted at init from the provider.
    public private(set) var availableApps: [TargetApp]
    /// Whether Accessibility (TCC) trust is granted — gates the "Rearrange now" button.
    public private(set) var isAccessibilityTrusted: Bool
    /// Whether the user has EVER granted Accessibility; latched by `syncTrust()` for `grantBroken`.
    public private(set) var wasTrusted: Bool
    /// Whether the app is registered to launch at login (source of truth = `LoginItem.status`).
    public private(set) var launchAtLogin: Bool
    /// The tile gap in points (#17a) — loaded from settings, tracked so the Stepper live-updates.
    /// Was an injected `let`; now user-state like `targetBundleID`. Clamped by `setGap`.
    public private(set) var gap: CGFloat
    /// The global hotkey (#25b) — loaded from settings, tracked so the recorder row live-updates.
    public private(set) var hotKey: HotKeyConfig
    /// Whether the current `hotKey` is actually registered with the OS — false if the combo was taken
    /// at launch or a re-registration failed, so the row can show "unavailable" instead of lying.
    public private(set) var hotKeyRegistered = false
    /// Opt-in drag-reorder (#26) — loaded from settings, tracked so the toggle live-updates. OFF by
    /// default; the live watchers (#26 later steps) only run when this is true.
    public private(set) var reorderOnDrag: Bool
    /// Which reorder strategy a drag uses (#27) — loaded from settings, tracked so the Picker updates.
    public private(set) var reorderStrategy: ReorderStrategy
    /// Whether Rearrange should also ask macOS to bring the selected target app forward (#36).
    /// Loaded from settings, tracked for the menu toggle. OFF by default to preserve current behavior.
    public private(set) var bringToFrontOnRearrange: Bool
    /// Result from the last attempted bring-to-front request (#36). Nil means no foreground request
    /// was made for the last Rearrange (setting off, or Accessibility unavailable).
    public private(set) var lastForegroundResult: TargetForegroundResult?

    /// The fix-it row's state (#23): trusted → no row; never granted → first-grant prompt; untrusted
    /// but previously granted → the honest grant-BROKEN message (moved/duplicate bundle). Computed
    /// over the two tracked vars, so it's Observation-reactive.
    public var accessibilityState: AccessibilityState {
        if isAccessibilityTrusted { return .trusted }
        return wasTrusted ? .grantBroken : .needsFirstGrant
    }

    /// User-visible status for failed best-effort app activation. Successful, skipped, or disabled
    /// focus requests stay quiet; only actionable failures surface in the Rearrange group.
    public var foregroundWarningMessage: String? {
        guard bringToFrontOnRearrange else { return nil }
        switch lastForegroundResult {
        case .frontmost, .none:
            return nil
        case .requestAcceptedButUnverified:
            return "macOS accepted the focus request, but TermTile could not verify the app came forward."
        case .notRunning:
            return "The selected app is not running."
        case .activationRejected:
            return "macOS rejected the focus request."
        }
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
    /// Optional Rearrange-time app activation port (#36). Nil in tests/gallery/selftest contexts so
    /// they do not foreground user apps or surface fake foreground warnings.
    @ObservationIgnored private let foregrounder: (any TargetAppForegrounding)?
    /// Monotonic guard for async foreground requests. Target/setting changes or a newer Rearrange
    /// invalidate older completions so stale app-focus warnings cannot reappear.
    @ObservationIgnored private var foregroundRequestGeneration = 0
    /// The Uninstaller — injected by the composition root (which supplies the real library +
    /// bundle URL), so the VM never touches `FileManager`/`Bundle.main` and stays test-injected.
    /// Optional: unbundled/test contexts leave it nil (uninstall is a no-op there).
    @ObservationIgnored private let uninstaller: Uninstaller?
    /// Set POST-init by the composition root (breaks the VM↔monitor init cycle): re-registers the
    /// live hotkey and returns whether it succeeded. `setHotKey` commits only on a `true` return.
    @ObservationIgnored public var onHotKeyChanged: (@Sendable (HotKeyConfig) -> Bool)?
    /// The opt-in drag-reorder monitor (#26). Injected at init (tests, a spy) OR set post-init by the
    /// composition root (production — its closures capture this VM, so it can't exist at init: the
    /// same cycle-break the hotkey uses). The VM owns its lifecycle via `syncReorderMonitor()`.
    @ObservationIgnored private var dragReorder: (any DragReorderControlling)?
    /// Clears stale macOS TCC rows for this bundle ID. Optional so selftest/gallery cannot mutate a
    /// developer's real permission database.
    @ObservationIgnored private let permissionRepairer: (any PermissionRepairing)?

    public init(
        settings: any SettingsStore,
        loginItem: any LoginItem,
        appsProvider: any TargetAppsProviding,
        isTrustedProbe: @escaping @Sendable () -> Bool,
        visibleFrame: CGRect,
        epsilon: CGFloat,
        makeActor: @escaping @Sendable (String) -> TilingActor,
        uninstaller: Uninstaller? = nil,
        foregrounder: (any TargetAppForegrounding)? = nil,
        dragReorder: (any DragReorderControlling)? = nil,
        permissionRepairer: (any PermissionRepairing)? = nil
    ) {
        let loaded = settings.load()
        self.settings = settings
        self.loginItem = loginItem
        self.isTrustedProbe = isTrustedProbe
        self.visibleFrame = visibleFrame
        self.epsilon = epsilon
        self.makeActor = makeActor
        self.uninstaller = uninstaller
        self.foregrounder = foregrounder
        self.dragReorder = dragReorder
        self.permissionRepairer = permissionRepairer
        self.targetBundleID = loaded.targetBundleID
        self.availableApps = appsProvider.runningTargetApps()
        self.isAccessibilityTrusted = false   // set by syncTrust() below (single source)
        self.wasTrusted = loaded.wasTrusted
        // #17a — user-state loaded like targetBundleID. Clamped on READ too: a tampered/downgraded
        // plist (gap=9999) would otherwise flow unclamped to TileLayout as a negative column width.
        self.gap = Self.clampedGap(CGFloat(loaded.gap))
        self.hotKey = loaded.hotKey           // #25b — user-state, loaded like targetBundleID
        self.reorderOnDrag = loaded.reorderOnDrag   // #26 — opt-in, off by default
        self.reorderStrategy = loaded.reorderStrategy   // #27 — user-selectable reorder behavior
        self.bringToFrontOnRearrange = loaded.bringToFrontOnRearrange
        self.lastForegroundResult = nil
        self.launchAtLogin = loginItem.status == .enabled
        self.actor = makeActor(loaded.targetBundleID)
        syncTrust()   // probe + latch at init — catches the trusted-at-launch / migrating case (#23 B2)
        syncReorderMonitor()   // #26 — start the drag monitor iff opted-in + trusted + granted
    }

    /// Start/stop drag-reorder to match state. Nothing watches the mouse until opt-in, AX trust, and
    /// Input Monitoring all hold.
    private func syncReorderMonitor() {
        guard let dragReorder else { return }
        if reorderOnDrag, isAccessibilityTrusted, dragReorder.inputMonitoringGranted {
            dragReorder.start()
        } else {
            // Missing Input Monitoring: request once so TermTile appears in the Settings pane. This is
            // intentionally independent of AX because the grants are separate.
            if reorderOnDrag, !dragReorder.inputMonitoringGranted {
                dragReorder.requestInputMonitoring()
            }
            dragReorder.stop()
        }
    }

    /// Wire the real drag-reorder controller AFTER init (production — it captures this VM). Triggers
    /// the first lifecycle sync.
    public func setDragReorder(_ controller: any DragReorderControlling) {
        dragReorder = controller
        syncReorderMonitor()
    }

    /// Shows the Input Monitoring fix-it row only when drag-reorder is on, AX is trusted, and IM is not.
    public var reorderNeedsInputMonitoring: Bool {
        reorderOnDrag && isAccessibilityTrusted && !(dragReorder?.inputMonitoringGranted ?? true)
    }

    /// The Privacy > Input Monitoring deep link the reorder fix-it row opens (sibling of the
    /// Accessibility one). `Privacy_ListenEvent` is the Input-Monitoring pane anchor.
    public var inputMonitoringSettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    }

    /// Repair path for users who granted an older/ad-hoc TermTile build and now have a stale TCC row:
    /// clear only TermTile's Accessibility grant, then re-probe. The caller opens Settings; this path
    /// deliberately does not request the AX prompt because that can leave both a Settings pane and a
    /// stale modal dialog on screen.
    @discardableResult
    public func repairAccessibilityPermission() -> [PermissionRepairReport] {
        guard let permissionRepairer else { return [] }
        let reports = permissionRepairer.reset([.accessibility])
        refreshTrust()
        return reports
    }

    /// Repair path for stale Input Monitoring grants. Reset the old row, then run the same request
    /// path used when drag-reorder is first enabled so macOS registers the current app in the pane.
    @discardableResult
    public func repairInputMonitoringPermission() -> [PermissionRepairReport] {
        guard let permissionRepairer else { return [] }
        let reports = permissionRepairer.reset([.inputMonitoring])
        syncReorderMonitor()
        return reports
    }

    /// Drag-reorder seams for the controller. Both hit the current actor, so target switches need no
    /// teardown; mouse-down captures identity and mouse-up verifies the frame really moved.
    public func resolveDraggedWindow(at point: CGPoint) async -> TrackedWindow? {
        await actor.trackedWindow(atFresh: point)
    }

    public func draggedWindowFrame(id: CGWindowID) async -> CGRect? {
        await actor.windowFrame(idFresh: id)
    }

    /// Reorder the dropped window at drag-END (fresh enumerate → nearest slot) using the user's chosen
    /// strategy (#27) on the current grid.
    public func reorderDroppedWindow(_ id: CGWindowID) async {
        await actor.reorderDropFresh(id, config: TileConfig(isEnabled: true, visibleFrame: visibleFrame, gap: gap),
                                     strategy: reorderStrategy)
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
        syncReorderMonitor()   // trust change may enable/disable the drag monitor (#26)
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
        clearForegroundResult()
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

    /// Change the global hotkey (#25b). Rejects an unbindable combo (no ⌥/⌃ — the ⌘Q footgun guard).
    /// Commits ONLY if re-registration SUCCEEDS: on failure (combo already taken) the old hotkey is
    /// left intact + still registered (the handler re-arms it), and nothing is persisted — so a bad
    /// pick can never leave the user with a dead, persisted hotkey (#25b B1).
    @discardableResult
    public func setHotKey(_ config: HotKeyConfig) -> Bool {
        guard config.isValid else { return false }
        let ok = onHotKeyChanged?(config) ?? true   // nil handler (tests) → treat as success
        // On failure the reconfigure rolled back + re-armed the OLD combo, so it's still registered —
        // leave hotKeyRegistered (and hotKey) as they were; don't mislabel the working hotkey.
        guard ok else { return false }
        hotKey = config
        hotKeyRegistered = true
        persist()
        return true
    }

    /// The composition root reports whether the current hotkey registered at launch, so the row can
    /// show "unavailable" when a persisted combo is taken.
    public func setHotKeyRegistered(_ registered: Bool) { hotKeyRegistered = registered }

    /// Toggle opt-in drag-reorder (#26). Persists the preference. The live watchers are started/
    /// stopped by the composition root's controller (a later #26 step) reacting to this state; the
    /// setting alone (this step) changes nothing observable.
    public func setReorderOnDrag(_ on: Bool) {
        reorderOnDrag = on
        persist()
        syncReorderMonitor()   // #26 — start/stop the monitor + prompt for Input Monitoring if it's the
    }                          // missing piece (the request lives in syncReorderMonitor so LAUNCH covers it too)

    /// Change the drag-reorder strategy (#27). Persists; the next drag uses it (no monitor restart —
    /// the strategy is read at reorder time).
    public func setReorderStrategy(_ strategy: ReorderStrategy) {
        reorderStrategy = strategy
        persist()
    }

    /// Toggle whether a manual Rearrange should also bring the selected target app forward (#36).
    /// This is user-state only: no tiling or activation happens until the next Rearrange command.
    public func setBringToFrontOnRearrange(_ on: Bool) {
        bringToFrontOnRearrange = on
        clearForegroundResult()
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
        clearForegroundResult()
        let targetBundleID = targetBundleID
        let actor = actor
        let foregrounder = foregrounder
        let config = TileConfig(isEnabled: true, visibleFrame: visibleFrame, gap: gap)
        let shouldBringToFront = bringToFrontOnRearrange && isAccessibilityTrusted
        let requestGeneration = foregroundRequestGeneration
        await actor.activate(config: config)
        if shouldBringToFront,
           let foregrounder,
           foregroundRequestIsCurrent(bundleID: targetBundleID, generation: requestGeneration) {
            let result = await foregrounder.bringToFront(bundleID: targetBundleID)
            if foregroundRequestIsCurrent(bundleID: targetBundleID, generation: requestGeneration) {
                lastForegroundResult = result
            }
        }
    }

    private func foregroundRequestIsCurrent(bundleID: String, generation: Int) -> Bool {
        generation == foregroundRequestGeneration
            && bundleID == targetBundleID
            && bringToFrontOnRearrange
            && isAccessibilityTrusted
    }

    private func clearForegroundResult() {
        foregroundRequestGeneration += 1
        lastForegroundResult = nil
    }

    /// One persist for ALL writes — carries the live `wasTrusted` so an unrelated save (e.g. a
    /// target-app change) never clobbers the latch back to false (#23 B1).
    private func persist() {
        settings.save(AppSettings(targetBundleID: targetBundleID, wasTrusted: wasTrusted,
                                  gap: Double(gap), hotKey: hotKey, reorderOnDrag: reorderOnDrag,
                                  reorderStrategy: reorderStrategy,
                                  bringToFrontOnRearrange: bringToFrontOnRearrange))
    }

    /// The PRODUCTION Accessibility-trust probe for the composition root to inject. Defined in Kit
    /// so it can close over the Kit-internal `AccessibilityTrust` (the executable never sees that
    /// type). `prompting: false` — a read-only status check that never pops the grant dialog on a
    /// menu open (the user reaches System Settings via the fix-it row's `Link` instead).
    public static let liveTrustProbe: @Sendable () -> Bool = { AccessibilityTrust.isTrusted(prompting: false) }
}
