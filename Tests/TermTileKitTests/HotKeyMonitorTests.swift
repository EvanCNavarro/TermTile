import Carbon.HIToolbox
import Testing
@testable import TermTileKit

/// #25 — the global hotkey. Only the pure config + the dispatch seam are unit-testable; the Carbon
/// `RegisterEventHotKey` registration + the C-callback routing of a real keypress are a live-only
/// surface (like `DragMonitor`/`AXWindowSystem`), proven by the PROVE (a real ⌃⌥⌘R press tiles).
@Suite("HotKeyMonitor — global hotkey")
struct HotKeyMonitorTests {
    @Test("default config is ⌘⌥T with Carbon modifier masks")
    func defaultConfig() {
        let c = HotKeyConfig.rearrange
        #expect(c.keyCode == UInt32(kVK_ANSI_T))                     // T
        #expect(c.modifiers == UInt32(cmdKey | optionKey))           // Carbon, not Cocoa
    }

    @Test("carbonModifiers maps Cocoa flags, ignoring stray bits")
    func carbonModifierMapping() {
        #expect(HotKeyConfig.carbonModifiers(from: [.command, .option]) == UInt32(cmdKey | optionKey))
        #expect(HotKeyConfig.carbonModifiers(from: [.control, .shift]) == UInt32(controlKey | shiftKey))
        // capsLock must NOT leak into the mask
        #expect(HotKeyConfig.carbonModifiers(from: [.command, .option, .capsLock]) == UInt32(cmdKey | optionKey))
    }

    @Test("isValid requires ⌥ or ⌃ (blocks the ⌘Q footgun class)")
    func validity() {
        #expect(HotKeyConfig(keyCode: 17, modifiers: UInt32(cmdKey | optionKey)).isValid)   // ⌘⌥T ✓
        #expect(HotKeyConfig(keyCode: 15, modifiers: UInt32(controlKey)).isValid)            // ⌃R ✓
        #expect(!HotKeyConfig(keyCode: 12, modifiers: UInt32(cmdKey)).isValid)               // ⌘Q ✗
        #expect(!HotKeyConfig(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)).isValid)    // ⌘⇧T ✗
    }

    @Test("displayString renders modifiers in macOS order + key glyph")
    func display() {
        #expect(HotKeyConfig.rearrange.displayString == "⌥⌘T")                                // ⌃⌥⇧⌘ order
        #expect(HotKeyConfig(keyCode: UInt32(kVK_Space),
                             modifiers: UInt32(controlKey | shiftKey)).displayString == "⌃⇧Space")
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

    // #25b SHOULD-FIX 1 — start() must REFUSE an invalid combo (⌘-only / modifier-less), even from a
    // tampered/downgraded plist that bypassed setHotKey, so it can't hijack a key system-wide.
    @Test("start() refuses an invalid (⌘-only) combo")
    func startRefusesInvalidCombo() {
        let monitor = HotKeyMonitor(config: HotKeyConfig(keyCode: 12, modifiers: UInt32(cmdKey)),
                                    onFire: {})
        #expect(monitor.start() == false)   // no ⌥/⌃ → not registered
        monitor.stop()
    }
}
