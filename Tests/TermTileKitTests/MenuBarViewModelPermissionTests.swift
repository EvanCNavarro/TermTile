import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// TRAP-23 follow-up: a fresh install that meets a stale Accessibility row (left by another build under the same
/// bundle ID) was stuck on "Allow Accessibility" — Settings already showed TermTile ON, so allowing did nothing, and
/// the reset only appeared for a copy that had once been trusted. TermTile can't read TCC, but it knows when it
/// sent the user to Settings: still untrusted after that means the entry is stale, so offer the reset.
@MainActor
@Suite("MenuBarViewModel — reset offered once Allow didn't take")
struct MenuBarViewModelPermissionTests {
    func makeVM(store: any SettingsStore = InMemorySettingsStore(), trusted: Bool) -> MenuBarViewModel {
        let fake = InMemoryWindowSystem(windows: [])
        return MenuBarViewModel(
            settings: store, loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: [TargetApp(bundleID: "com.googlecode.iterm2", name: "iTerm2")]),
            isTrustedProbe: { trusted }, visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000), epsilon: 2,
            makeActor: { _ in TilingActor(system: fake, epsilon: 2) })
    }

    @Test("never sent to Settings → plain first-grant prompt")
    func firstGrant() {
        #expect(makeVM(trusted: false).accessibilityState == .needsFirstGrant)
    }

    @Test("sent to Settings and still untrusted → reset offered")
    func stillUntrustedAfterAllow() {
        let vm = makeVM(trusted: false)
        vm.noteAccessibilitySettingsOpened()
        vm.refreshTrust()
        #expect(vm.accessibilityState == .grantBroken)
    }

    @Test("sent to Settings and now trusted → no notice")
    func trustedAfterAllow() {
        let vm = makeVM(trusted: true)
        vm.noteAccessibilitySettingsOpened()
        #expect(vm.accessibilityState == .trusted)
    }

    @Test("the flag is per launch: not saved, a relaunch starts at the first-grant prompt")
    func notPersisted() {
        let store = InMemorySettingsStore()
        let first = makeVM(store: store, trusted: false)
        first.noteAccessibilitySettingsOpened()
        #expect(makeVM(store: store, trusted: false).accessibilityState == .needsFirstGrant)
    }
}
