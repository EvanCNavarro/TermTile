import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// #12c — the menu-bar shell's composition/presentation logic (ADR-0001 imperative shell). The
/// `MenuBarViewModel` binds the ports #12a/#12b/#19 built (`SettingsStore`, `LoginItem`,
/// `TargetAppsProviding`, an injected trust probe, and a `makeActor` factory) into the state the
/// SwiftUI menu renders and the actions it invokes. Proven here against the in-memory fakes — the
/// LIVE app-launch + status-item enumeration is the beat's PROVE (docs/verification/task12c-*.md).
///
/// R1 (audit): `visibleFrame` is INJECTED, never read from a real `NSScreen`, so the keystone is
/// deterministic and asserts EXACT grid targets. R2: `setEnabled` AWAITS `activate`, so the fake's
/// `recordedWrites` is committed by the time a `@MainActor` test reads it. R3: #12c drives only
/// `activate()` — no `run()`/live events (that leak-prone path is #14).
@MainActor
@Suite("MenuBarViewModel — shell wiring")
struct MenuBarViewModelTests {
    // Keystone geometry (mirrors TilingActorTests): a known visibleFrame → known slot targets.
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let gap: CGFloat = 10
    let eps: CGFloat = 2
    func targets(_ n: Int) -> [CGRect] { TileLayout.frames(count: n, visibleFrame: visible, gap: gap) }
    func win(_ id: CGWindowID, _ r: CGRect) -> TrackedWindow { TrackedWindow(id: id, frame: r) }
    func off(_ id: CGWindowID) -> TrackedWindow { win(id, CGRect(x: 0, y: 0, width: 100, height: 100)) }

    /// Build a view model wired to fakes. `windows` seeds the fake window system the `makeActor`
    /// factory closes over; `store`/`login`/`apps`/`trusted` default to sane fakes. The factory
    /// ignores its bundleID argument (all targets resolve to the same fake) — target-switch is
    /// exercised by re-tiling, not by a real adapter (live re-target is #14).
    func makeVM(
        windows: [TrackedWindow] = [],
        store: any SettingsStore = InMemorySettingsStore(),
        login: any LoginItem = InMemoryLoginItem(),
        apps: [TargetApp] = [TargetApp(bundleID: "com.googlecode.iterm2", name: "iTerm2")],
        trusted: Bool = false
    ) -> (vm: MenuBarViewModel, fake: InMemoryWindowSystem) {
        let fake = InMemoryWindowSystem(windows: windows)
        let vm = MenuBarViewModel(
            settings: store,
            loginItem: login,
            appsProvider: InMemoryTargetAppsProvider(seed: apps),
            isTrustedProbe: { trusted },
            visibleFrame: visible,
            gap: gap,
            epsilon: eps,
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps, ttlSeconds: 100) })
        return (vm, fake)
    }

    // KEYSTONE — toggle ON persists isEnabled AND drives TilingActor.activate: the fake receives
    // writes AT THE GRID TARGETS. This is the toggle→activate wire (the one flip that reddens it:
    // make setEnabled always activate(.disabled) → zero writes).
    @Test("keystone: toggle-on persists and tiles at grid targets")
    func toggleOnPersistsAndTiles() async {
        let seed = [off(1), off(2), off(3)]
        let (vm, fake) = makeVM(windows: seed)
        let t = targets(3)
        for k in 0..<3 { #expect(seed[k].frame != t[k]) }  // genuinely off-grid → writes provable

        await vm.setEnabled(true)

        #expect(vm.isEnabled)
        #expect(vm.settings.load().isEnabled)              // persisted through the port
        let writes = await fake.recordedWrites
        #expect(writes.count == 3)
        #expect(Set(writes.map(\.id)) == Set([1, 2, 3]))
        for w in writes { #expect(w.target == t[Int(w.id) - 1]) }  // EXACT targets (R1)
    }

    // Toggle OFF is inert (TileEngine.retileCommands line-21 guard): a fresh default-disabled vm
    // that goes false issues ZERO writes (no untile, "Off = no rigid behavior at all").
    @Test("toggle-off is inert — zero writes")
    func toggleOffIsInert() async {
        let seed = [off(1), off(2)]
        let (vm, fake) = makeVM(windows: seed)
        await vm.setEnabled(false)
        #expect(!vm.isEnabled)
        #expect(!vm.settings.load().isEnabled)
        let writes = await fake.recordedWrites
        #expect(writes.isEmpty)
    }

    @Test("init loads persisted settings")
    func initLoadsPersistedSettings() {
        let store = InMemorySettingsStore()
        store.save(AppSettings(isEnabled: true, targetBundleID: "com.example.other"))
        let (vm, _) = makeVM(store: store)
        #expect(vm.isEnabled)
        #expect(vm.targetBundleID == "com.example.other")
    }

    @Test("picker default is iTerm2 on a fresh store")
    func pickerDefaultIsITerm2() {
        let (vm, _) = makeVM()
        #expect(vm.targetBundleID == "com.googlecode.iterm2")
    }

    @Test("set target persists and, when enabled, re-tiles")
    func setTargetPersistsAndReTiles() async {
        let seed = [off(1), off(2)]
        let (vm, fake) = makeVM(windows: seed)
        await vm.setEnabled(true)
        let before = await fake.recordedWrites.count
        await vm.setTarget("com.example.other")
        #expect(vm.targetBundleID == "com.example.other")
        #expect(vm.settings.load().targetBundleID == "com.example.other")
        let after = await fake.recordedWrites.count
        #expect(after > before)  // enabled → the rebuilt actor re-tiled the new target's windows
    }

    @Test("set target persists but does NOT tile when disabled")
    func setTargetNoTileWhenDisabled() async {
        let seed = [off(1)]
        let (vm, fake) = makeVM(windows: seed)
        await vm.setTarget("com.example.other")
        #expect(vm.targetBundleID == "com.example.other")
        let writes = await fake.recordedWrites
        #expect(writes.isEmpty)
    }

    @Test("launch-at-login toggles the login-item registration")
    func launchAtLoginTogglesRegistration() {
        let login = InMemoryLoginItem(initial: .notRegistered)
        let (vm, _) = makeVM(login: login)
        #expect(!vm.launchAtLogin)
        vm.setLaunchAtLogin(true)
        #expect(login.status == .enabled)
        #expect(vm.launchAtLogin)
        vm.setLaunchAtLogin(false)
        #expect(login.status == .notRegistered)
        #expect(!vm.launchAtLogin)
    }

    /// A mutable flag the `@Sendable` probe closure can read — `@unchecked Sendable` is honest
    /// here: the test only touches it on the main actor (no real concurrency).
    final class Flag: @unchecked Sendable { var value: Bool; init(_ v: Bool) { value = v } }

    @Test("accessibility trust reflects the injected probe and refreshes")
    func trustReflectsProbe() {
        let flag = Flag(false)
        let fake = InMemoryWindowSystem(windows: [])
        let vm = MenuBarViewModel(
            settings: InMemorySettingsStore(),
            loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: []),
            isTrustedProbe: { flag.value },
            visibleFrame: visible, gap: gap, epsilon: eps,
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps, ttlSeconds: 100) })
        #expect(!vm.isAccessibilityTrusted)     // probe false → fix-it row shows
        flag.value = true
        vm.refreshTrust()
        #expect(vm.isAccessibilityTrusted)       // after the user grants + menu re-opens
    }

    @Test("available apps come from the provider")
    func availableAppsFromProvider() {
        let apps = [TargetApp(bundleID: "a", name: "Alpha"), TargetApp(bundleID: "b", name: "Beta")]
        let (vm, _) = makeVM(apps: apps)
        #expect(vm.availableApps == apps)
    }

    @Test("accessibility settings URL is the Privacy_Accessibility deep link")
    func accessibilityURLIsDeepLink() {
        let (vm, _) = makeVM()
        #expect(vm.accessibilitySettingsURL.absoluteString
            .contains("Privacy_Accessibility"))
    }

    // "Rearrange now" — the one-shot verb button: tiles at grid targets even with the mode
    // toggle OFF, and neither flips isEnabled nor persists any settings change.
    @Test("rearrangeNow tiles while disabled and leaves mode/persistence untouched")
    func rearrangeNowTilesWhileDisabled() async {
        let store = InMemorySettingsStore()
        let seed = [off(1), off(2), off(3)]
        let (vm, fake) = makeVM(windows: seed, store: store)
        #expect(vm.isEnabled == false)
        let before = store.load()

        await vm.rearrangeNow()

        let t = targets(3)
        let writes = await fake.recordedWrites
        #expect(writes.count == 3)
        for (k, w) in writes.enumerated() { #expect(w.target == t[k]) }
        #expect(vm.isEnabled == false)                    // mode untouched
        #expect(store.load().isEnabled == before.isEnabled) // nothing persisted
    }
}
