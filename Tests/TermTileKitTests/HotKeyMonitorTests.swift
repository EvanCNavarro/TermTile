import Carbon.HIToolbox
import Testing
@testable import TermTileKit

/// #25 — the global hotkey. Only the pure config + the dispatch seam are unit-testable; the Carbon
/// `RegisterEventHotKey` registration + the C-callback routing of a real keypress are a live-only
/// surface (like `DragMonitor`/`AXWindowSystem`), proven by the PROVE (a real ⌃⌥⌘R press tiles).
@Suite("HotKeyMonitor — global hotkey")
struct HotKeyMonitorTests {
    @Test("default config is ⌃⌥⌘R with Carbon modifier masks")
    func defaultConfig() {
        let c = HotKeyConfig.rearrange
        #expect(c.keyCode == UInt32(kVK_ANSI_R))                               // R
        #expect(c.modifiers == UInt32(controlKey | optionKey | cmdKey))        // Carbon, not Cocoa
    }

    @Test("fire() dispatches to onFire")
    func fireDispatches() {
        final class Box: @unchecked Sendable { var hit = false }
        let box = Box()
        let monitor = HotKeyMonitor(config: .rearrange, onFire: { box.hit = true })
        monitor.fire()   // the seam the @convention(c) callback invokes on a real keypress
        #expect(box.hit)
    }

    @Test("HotKeyConfig round-trips its fields")
    func configRoundTrips() {
        let c = HotKeyConfig(keyCode: 99, modifiers: UInt32(shiftKey))
        #expect(c.keyCode == 99)
        #expect(c.modifiers == UInt32(shiftKey))
    }

    @Test("stop() before start() is a safe no-op")
    func stopBeforeStartIsSafe() {
        let monitor = HotKeyMonitor(onFire: {})
        monitor.stop()   // must not crash / touch nil refs (the idempotency the deinit relies on)
    }
}
