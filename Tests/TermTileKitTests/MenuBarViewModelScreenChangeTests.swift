import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// The screen can change size while TermTile runs (a remote-desktop client resizing the display, a monitor
/// swap). The grid must be laid out for the screen as it is at rearrange time, not as it was at launch: the VM
/// asks `visibleFrameProvider` on every rearrange.
@MainActor
@Suite("MenuBarViewModel — screen size read per rearrange")
struct MenuBarViewModelScreenChangeTests {
    final class Screen: @unchecked Sendable { var frame: CGRect; init(_ frame: CGRect) { self.frame = frame } }

    let launch = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let resized = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let gap: CGFloat = 8

    func makeVM(windows: [TrackedWindow], screen: Screen) -> (MenuBarViewModel, InMemoryWindowSystem) {
        let fake = InMemoryWindowSystem(windows: windows)
        let vm = MenuBarViewModel(
            settings: InMemorySettingsStore(), loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: [TargetApp(bundleID: "com.googlecode.iterm2", name: "iTerm2")]),
            isTrustedProbe: { false }, visibleFrame: launch, epsilon: 2,
            makeActor: { _ in TilingActor(system: fake, epsilon: 2) },
            visibleFrameProvider: { screen.frame })
        return (vm, fake)
    }

    @Test("a rearrange after the screen grows lays the grid out on the new size")
    func rearrangeUsesCurrentScreen() async {
        let windows = [1, 2, 3].map { TrackedWindow(id: CGWindowID($0), frame: CGRect(x: 0, y: 0, width: 50, height: 50)) }
        let screen = Screen(launch)
        let (vm, fake) = makeVM(windows: windows, screen: screen)
        screen.frame = resized

        await vm.rearrangeNow()

        let want = TileLayout.frames(count: 3, visibleFrame: resized, gap: gap)
        let writes = await fake.recordedWrites
        #expect(writes.count == 3)
        for write in writes { #expect(write.target == want[Int(write.id) - 1]) }
    }

    @Test("without a provider the launch frame is used, as before")
    func fixedFrameFallback() async {
        let windows = [TrackedWindow(id: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 50))]
        let fake = InMemoryWindowSystem(windows: windows)
        let vm = MenuBarViewModel(
            settings: InMemorySettingsStore(), loginItem: InMemoryLoginItem(),
            appsProvider: InMemoryTargetAppsProvider(seed: [TargetApp(bundleID: "com.googlecode.iterm2", name: "iTerm2")]),
            isTrustedProbe: { false }, visibleFrame: launch, epsilon: 2,
            makeActor: { _ in TilingActor(system: fake, epsilon: 2) })

        await vm.rearrangeNow()

        let writes = await fake.recordedWrites
        #expect(writes.map(\.target) == TileLayout.frames(count: 1, visibleFrame: launch, gap: gap))
    }
}
