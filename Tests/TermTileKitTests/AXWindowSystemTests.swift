import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// #19a — the production `AXWindowSystem` adapter's non-live, deterministic invariants. Live AX
/// behavior (real iTerm2 enumerate + grid snap) is proven by the `AXProbe livecheck` harness +
/// screencapture (FL-1, the beat's PROVE), not here — an AX read needs a running target app and
/// Accessibility trust. What IS unit-testable without either: a not-running target yields an
/// empty enumeration (no crash, no permission required — the guard short-circuits before any AX
/// call), and `events()` is a finished-empty stub this beat (the real bridge is #19b).
@Suite("AXWindowSystem — adapter invariants (non-live)")
struct AXWindowSystemTests {
    @Test("not-running target: tileableWindows is empty, readFrame is nil")
    func notRunningIsEmpty() async {
        let adapter = AXWindowSystem(bundleID: "dev.ecn.apps.termtile.no-such-app")
        #expect(await adapter.tileableWindows().isEmpty)
        #expect(await adapter.readFrame(12345) == nil)
    }

    @Test("not-running target: writeFrame fails cleanly (no window to write)")
    func notRunningWriteFails() async {
        let adapter = AXWindowSystem(bundleID: "dev.ecn.apps.termtile.no-such-app")
        let ok = await adapter.writeFrame(12345, to: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(ok == false)
    }

    @Test("events() stub finishes immediately (#19b wires the real AXObserver bridge)")
    func eventsStubFinishes() async {
        let adapter = AXWindowSystem(bundleID: "dev.ecn.apps.termtile.no-such-app")
        var count = 0
        for await _ in adapter.events() { count += 1 }
        #expect(count == 0)   // finished-empty stream → the for-await returns at once
    }
}
