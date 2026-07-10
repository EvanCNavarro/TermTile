import Carbon.HIToolbox
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
            epsilon: eps,
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps) },
            uninstaller: uninstaller)
        return (vm, fake)
    }

    // KEYSTONE — "Rearrange now" drives TilingActor.activate: the fake receives writes AT THE GRID
    // TARGETS. This is the button→activate wire (the flip that reddens it: make rearrangeNow
    // activate(.disabled) → zero writes).
    @Test("keystone: rearrange-now tiles at grid targets")
    func rearrangeNowTilesAtGridTargets() async {
        let seed = [off(1), off(2), off(3)]
        // Seed gap=10 (≠ the 8 default) into the store so the VM LOADS it — this also proves the
        // #17a settings→VM→TileConfig→layout flow: the EXACT targets below use the same gap.
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: false, gap: Double(gap), hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        let (vm, fake) = makeVM(windows: seed, store: store)
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
        store.save(AppSettings(targetBundleID: "com.example.other", wasTrusted: false, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
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
            visibleFrame: visible, epsilon: eps,
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps) })
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

    // #23 — a save-counting SettingsStore spy, to assert the wasTrusted latch fires exactly once.
    final class SaveSpyStore: SettingsStore, @unchecked Sendable {
        private let lock = NSLock()
        private var current: AppSettings?
        private(set) var saveCount = 0
        init(_ initial: AppSettings? = nil) { current = initial }
        func load() -> AppSettings { lock.withLock { current ?? .defaults } }
        func save(_ s: AppSettings) { lock.withLock { current = s; saveCount += 1 } }
        func purge() { lock.withLock { current = nil } }
    }

    // B2 fix — a trusted-at-launch user (incl. migrating users: wasTrusted key absent → false)
    // latches wasTrusted=true ONCE at init, so a later grant-break is recognised as grantBroken.
    @Test("latches wasTrusted at init when already trusted")
    func latchesAtInit() {
        let spy = SaveSpyStore()  // wasTrusted absent → false
        let (vm, _) = makeVM(store: spy, trusted: true)
        #expect(vm.accessibilityState == .trusted)
        #expect(spy.saveCount == 1)                 // latched exactly once
        #expect(spy.load().wasTrusted == true)
    }

    // Idempotent on the PERSISTED flag — repeated refreshTrust after true writes nothing more.
    @Test("latch is idempotent")
    func latchIdempotent() {
        let spy = SaveSpyStore(AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: true, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        let (vm, _) = makeVM(store: spy, trusted: true)
        let base = spy.saveCount                    // 0 — already true, no init latch
        vm.refreshTrust(); vm.refreshTrust()
        #expect(spy.saveCount == base)
    }

    // Untrusted never writes; state is needsFirstGrant (never granted) or grantBroken (was granted).
    @Test("untrusted: needsFirstGrant vs grantBroken, never writes")
    func untrustedStates() {
        let spy1 = SaveSpyStore()
        let (vm1, _) = makeVM(store: spy1, trusted: false)
        #expect(vm1.accessibilityState == .needsFirstGrant)
        #expect(spy1.saveCount == 0)
        let spy2 = SaveSpyStore(AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: true, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        let (vm2, _) = makeVM(store: spy2, trusted: false)
        #expect(vm2.accessibilityState == .grantBroken)
    }

    // THE named scenario — a grant that BREAKS at runtime (moved/duplicate bundle): start trusted
    // (latch), the probe flips false, refreshTrust → grantBroken, wasTrusted STAYS true, no rewrite.
    @Test("runtime revoke: wasTrusted stays true → grantBroken, no rewrite")
    func revokeBecomesGrantBroken() {
        let flag = Flag(true)
        let spy = SaveSpyStore()
        let fake = InMemoryWindowSystem(windows: [])
        let vm = MenuBarViewModel(
            settings: spy, loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: []),
            isTrustedProbe: { flag.value },
            visibleFrame: visible, epsilon: eps,
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps) })
        #expect(vm.accessibilityState == .trusted)
        let afterLatch = spy.saveCount            // 1 — latched at init
        flag.value = false                        // the grant breaks
        vm.refreshTrust()
        #expect(vm.accessibilityState == .grantBroken)   // honest state, not needsFirstGrant
        #expect(spy.load().wasTrusted == true)           // latch survives the break
        #expect(spy.saveCount == afterLatch)             // revoke writes nothing
    }

    // #26 — reorderOnDrag opt-in: off by default; setReorderOnDrag persists + carries all fields.
    @Test("reorderOnDrag off by default; setReorderOnDrag persists")
    func setReorderOnDragPersists() {
        let store = InMemorySettingsStore()
        let (vm, _) = makeVM(store: store)
        #expect(!vm.reorderOnDrag)                         // OFF by default — no daemon/permission
        vm.setReorderOnDrag(true)
        #expect(vm.reorderOnDrag)
        #expect(store.load().reorderOnDrag == true)        // persisted
        vm.setReorderOnDrag(false)
        #expect(store.load().reorderOnDrag == false)
    }

    // #26 S3b — opting in without Input Monitoring must PROMPT (register in the pane), not silently
    // sit on a non-prompting preflight that never adds the app to the approval list.
    @Test("enabling reorder-on-drag requests Input Monitoring when it isn't granted")
    func enablingReorderRequestsInputMonitoringWhenUngranted() {
        let (vm, spy) = makeVMWithReorder(store: InMemorySettingsStore(), trusted: true, granted: false)
        vm.setReorderOnDrag(true)
        #expect(spy.requestCount == 1)
    }

    @Test("enabling reorder-on-drag does NOT request Input Monitoring when already granted")
    func enablingReorderDoesNotRequestWhenGranted() {
        let (vm, spy) = makeVMWithReorder(store: InMemorySettingsStore(), trusted: true, granted: true)
        vm.setReorderOnDrag(true)
        #expect(spy.requestCount == 0)
    }

    // #27 — reorderStrategy defaults adaptive; setReorderStrategy persists the pick.
    @Test("reorderStrategy defaults adaptive; setReorderStrategy persists")
    func setReorderStrategyPersists() {
        let store = InMemorySettingsStore()
        let (vm, _) = makeVM(store: store)
        #expect(vm.reorderStrategy == .adaptive)           // the intuitive default
        vm.setReorderStrategy(.swap)
        #expect(vm.reorderStrategy == .swap)
        #expect(store.load().reorderStrategy == .swap)      // persisted
    }

    // #26 — a spy drag-reorder controller: records start/stop so the VM lifecycle is unit-provable.
    @MainActor
    final class SpyDragReorder: DragReorderControlling {
        var inputMonitoringGranted: Bool
        private(set) var isRunning = false
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var requestCount = 0
        init(granted: Bool) { inputMonitoringGranted = granted }
        func start() -> Bool { startCount += 1; isRunning = true; return true }
        func stop() { stopCount += 1; isRunning = false }
        func requestInputMonitoring() { requestCount += 1 }
    }

    func makeVMWithReorder(store: InMemorySettingsStore, trusted: Bool, granted: Bool)
        -> (MenuBarViewModel, SpyDragReorder) {
        let fake = InMemoryWindowSystem(windows: [])
        let spy = SpyDragReorder(granted: granted)
        let vm = MenuBarViewModel(
            settings: store, loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: []),
            isTrustedProbe: { trusted }, visibleFrame: visible, epsilon: eps,
            makeActor: { _ in TilingActor(system: fake, epsilon: self.eps) },
            dragReorder: spy)
        return (vm, spy)
    }

    // The monitor runs ONLY when opted-in AND trusted AND Input Monitoring granted — never a
    // half-run. Toggling / a denied grant / no-trust all leave it stopped.
    @Test("drag monitor starts only on opt-in ∧ trusted ∧ granted; stops otherwise")
    func reorderMonitorLifecycle() {
        // opted-in at launch (seeded) + trusted + granted → started at init
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.x", wasTrusted: true, gap: 8,
                               hotKey: .rearrange, reorderOnDrag: true, reorderStrategy: .swap))
        let (vm, spy) = makeVMWithReorder(store: store, trusted: true, granted: true)
        #expect(spy.isRunning)
        vm.setReorderOnDrag(false)               // toggle off → stops
        #expect(!spy.isRunning)
        vm.setReorderOnDrag(true)                // toggle on → starts
        #expect(spy.isRunning)

        // granted=false → NEVER starts (no half-run), even opted-in + trusted
        let (_, spyDenied) = makeVMWithReorder(store: store, trusted: true, granted: false)
        #expect(!spyDenied.isRunning)
        // untrusted → never starts
        let (_, spyUntrusted) = makeVMWithReorder(store: store, trusted: false, granted: true)
        #expect(!spyUntrusted.isRunning)
    }

    // #26 S3 — opted-in + trusted but Input Monitoring NOT granted → the UI must show a fix-it row
    // (not silently no-op). Off, or granted, → no fix-it.
    @Test("reorderNeedsInputMonitoring: on + trusted + not-granted only")
    func reorderNeedsInputMonitoringState() {
        let on = InMemorySettingsStore()
        on.save(AppSettings(targetBundleID: "com.x", wasTrusted: true, gap: 8,
                            hotKey: .rearrange, reorderOnDrag: true, reorderStrategy: .swap))
        #expect(makeVMWithReorder(store: on, trusted: true, granted: false).0.reorderNeedsInputMonitoring)
        #expect(!makeVMWithReorder(store: on, trusted: true, granted: true).0.reorderNeedsInputMonitoring)
        #expect(!makeVMWithReorder(store: on, trusted: false, granted: false).0.reorderNeedsInputMonitoring)
        // off by default → never
        #expect(!makeVMWithReorder(store: InMemorySettingsStore(), trusted: true, granted: false)
            .0.reorderNeedsInputMonitoring)
    }

    @Test("input-monitoring settings URL is the Privacy_ListenEvent deep link")
    func inputMonitoringURLIsDeepLink() {
        #expect(makeVM().0.inputMonitoringSettingsURL.absoluteString.contains("Privacy_ListenEvent"))
    }

    // #25b — setHotKey: valid combo commits + persists + fires the change handler; invalid is
    // rejected; a reconfigure FAILURE (combo taken) does NOT commit or persist (the B1 guard).
    @Test("setHotKey commits + persists + fires the handler on a valid combo")
    func setHotKeyValid() {
        let store = InMemorySettingsStore()
        let (vm, _) = makeVM(store: store)
        final class Box: @unchecked Sendable { var got: HotKeyConfig? }
        let box = Box()
        vm.onHotKeyChanged = { c in box.got = c; return true }   // reconfigure "succeeds"
        let combo = HotKeyConfig(keyCode: 15, modifiers: UInt32(controlKey | optionKey))   // ⌃⌥R
        #expect(vm.setHotKey(combo) == true)
        #expect(vm.hotKey == combo)
        #expect(store.load().hotKey == combo)      // persisted
        #expect(box.got == combo)                  // handler fired
        #expect(vm.hotKeyRegistered)
    }

    @Test("setHotKey rejects an invalid combo (no ⌥/⌃) — the ⌘Q footgun guard")
    func setHotKeyInvalid() {
        let (vm, _) = makeVM()
        let before = vm.hotKey
        #expect(vm.setHotKey(HotKeyConfig(keyCode: 12, modifiers: UInt32(cmdKey))) == false)  // ⌘Q
        #expect(vm.hotKey == before)               // unchanged
    }

    @Test("setHotKey does NOT commit when re-registration fails; the working hotkey stays registered")
    func setHotKeyReconfigureFails() {
        let store = InMemorySettingsStore()
        let (vm, _) = makeVM(store: store)
        vm.setHotKeyRegistered(true)               // a currently-working hotkey (the common case)
        let before = vm.hotKey
        vm.onHotKeyChanged = { _ in false }         // the new combo is taken → reconfigure rolls back
        let combo = HotKeyConfig(keyCode: 15, modifiers: UInt32(controlKey | optionKey))
        #expect(vm.setHotKey(combo) == false)
        #expect(vm.hotKey == before)               // NOT changed
        #expect(store.load().hotKey == before)     // NOT persisted → no dead-hotkey on relaunch
        #expect(vm.hotKeyRegistered)               // old combo re-armed → still registered, not mislabeled
    }

    // B1 guard — setTarget must NOT clobber a latched wasTrusted back to false.
    @Test("setTarget preserves wasTrusted")
    func setTargetPreservesWasTrusted() async {
        let spy = SaveSpyStore()
        let (vm, _) = makeVM(store: spy, trusted: true)   // latches wasTrusted=true at init
        await vm.setTarget("com.example.other")
        #expect(spy.load().wasTrusted == true)            // not wiped
        #expect(spy.load().targetBundleID == "com.example.other")
    }

    // #17a — gap loads from settings, clamps to gapRange, persists; manual model (no auto-tile).
    @Test("gap loads from settings")
    func gapLoadsFromSettings() {
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: false, gap: 24, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        let (vm, _) = makeVM(store: store)
        #expect(vm.gap == 24)
    }

    // A tampered/downgraded plist could hold an out-of-range gap — it must be clamped on LOAD too,
    // so a negative column width never reaches TileLayout.
    @Test("out-of-range persisted gap is clamped on load")
    func outOfRangeLoadedGapClamped() {
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: false, gap: 9999, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        let (vm, _) = makeVM(store: store)
        #expect(vm.gap == 40)                             // clamped, not 9999
    }

    @Test("setGap clamps to range and persists")
    func setGapClampsAndPersists() {
        let store = InMemorySettingsStore()
        let (vm, _) = makeVM(store: store)
        vm.setGap(20)
        #expect(vm.gap == 20)
        #expect(store.load().gap == 20)                   // persisted
        vm.setGap(-5);  #expect(vm.gap == 0)              // clamp low
        vm.setGap(999); #expect(vm.gap == 40)             // clamp high
        #expect(store.load().gap == 40)
    }

    // Manual model — setGap persists but does NOT auto-tile (like setTargetPersistsNoTile).
    @Test("setGap does not auto-tile")
    func setGapDoesNotAutoTile() async {
        let (vm, fake) = makeVM(windows: [off(1)])
        vm.setGap(16)
        let writes = await fake.recordedWrites
        #expect(writes.isEmpty)
    }

    // B1-style guard both ways — the single persist() carries all fields, no cross-clobber.
    @Test("setGap preserves target + wasTrusted; setTarget preserves gap")
    func persistCarriesAllFields() async {
        let spy = SaveSpyStore()
        let (vm, _) = makeVM(store: spy, trusted: true)   // latch wasTrusted=true
        vm.setGap(12)
        #expect(spy.load().wasTrusted == true)            // gap change didn't clobber the latch
        #expect(spy.load().targetBundleID == "com.googlecode.iterm2")
        await vm.setTarget("com.example.other")
        #expect(spy.load().gap == 12)                     // target change didn't clobber gap
    }
}
