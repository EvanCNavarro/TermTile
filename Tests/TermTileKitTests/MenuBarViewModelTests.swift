import CoreGraphics
import Foundation
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
/// deterministic and asserts EXACT grid targets. R2: `rearrangeNow` AWAITS `activate`, so the fake's
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
        trusted: Bool = false,
        uninstaller: Uninstaller? = nil
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
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps, ttlSeconds: 100) },
            uninstaller: uninstaller)
        return (vm, fake)
    }

    // KEYSTONE — "Rearrange now" drives TilingActor.activate: the fake receives writes AT THE GRID
    // TARGETS. This is the button→activate wire (the flip that reddens it: make rearrangeNow
    // activate(.disabled) → zero writes).
    @Test("keystone: rearrange-now tiles at grid targets")
    func rearrangeNowTilesAtGridTargets() async {
        let seed = [off(1), off(2), off(3)]
        let (vm, fake) = makeVM(windows: seed)
        let t = targets(3)
        for k in 0..<3 { #expect(seed[k].frame != t[k]) }  // genuinely off-grid → writes provable

        await vm.rearrangeNow()

        let writes = await fake.recordedWrites
        #expect(writes.count == 3)
        #expect(Set(writes.map(\.id)) == Set([1, 2, 3]))
        for w in writes { #expect(w.target == t[Int(w.id) - 1]) }  // EXACT targets (R1)
    }

    @Test("init loads persisted target")
    func initLoadsPersistedSettings() {
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.example.other"))
        let (vm, _) = makeVM(store: store)
        #expect(vm.targetBundleID == "com.example.other")
    }

    @Test("picker default is iTerm2 on a fresh store")
    func pickerDefaultIsITerm2() {
        let (vm, _) = makeVM()
        #expect(vm.targetBundleID == "com.googlecode.iterm2")
    }

    // Manual model: set target persists + rebuilds the actor, but does NOT tile — tiling only
    // happens when the user presses "Rearrange now".
    @Test("set target persists and does NOT auto-tile")
    func setTargetPersistsNoTile() async {
        let seed = [off(1)]
        let (vm, fake) = makeVM(windows: seed)
        await vm.setTarget("com.example.other")
        #expect(vm.targetBundleID == "com.example.other")
        #expect(vm.settings.load().targetBundleID == "com.example.other")
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

    // "Rearrange now" persists nothing — it's a pure action, not a setting.
    @Test("rearrangeNow does not persist any settings change")
    func rearrangeNowPersistsNothing() async {
        let store = InMemorySettingsStore()
        let (vm, _) = makeVM(windows: [off(1)], store: store)
        let before = store.load()
        await vm.rearrangeNow()
        #expect(store.load() == before)
    }

    // uninstall() forwards to the injected Uninstaller and returns its outcome; nil when none.
    @Test("uninstall routes to the injected uninstaller")
    func uninstallRoutes() throws {
        let lib = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-uninstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lib) }
        let u = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: InMemoryLoginItem(),
                            settings: InMemorySettingsStore(), bundleURL: nil, trash: { _ in })
        let (vm, _) = makeVM(uninstaller: u)
        let outcome = vm.uninstall()
        #expect(outcome != nil)
        #expect(outcome?.tccResetBundleID == AppIdentity.bundleID)
        #expect(outcome?.isClean == true)   // nothing to remove in the empty temp lib → clean
    }

    @Test("uninstall is a no-op (nil) when no uninstaller is injected")
    func uninstallNilWhenAbsent() {
        let (vm, _) = makeVM()   // no uninstaller
        #expect(vm.uninstall() == nil)
    }
}
