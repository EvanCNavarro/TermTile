import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// #19a/#19b — the production `AXWindowSystem` adapter's non-live, deterministic invariants. Live
/// AX behavior (real iTerm2 enumerate + grid snap + the #19b AXObserver event bridge) is proven by
/// the `AXProbe livecheck*` harnesses + screencapture (FL-1, the beats' PROVE), not here — an AX
/// read/observe needs a running target app and Accessibility trust. What IS unit-testable without
/// either: a not-running target yields an empty enumeration (no crash, no permission required — the
/// guard short-circuits before any AX call), and `events()` on a not-running target returns a
/// finished-empty stream (no observer is installed, so the `for await` returns at once — no hang).
@Suite("AXWindowSystem — adapter invariants (non-live)")
struct AXWindowSystemTests {
    @Test("not-running target: tileableWindows is empty")
    func notRunningIsEmpty() async {
        let adapter = AXWindowSystem(bundleID: "dev.ecn.apps.termtile.no-such-app")
        #expect(await adapter.tileableWindows().isEmpty)
    }

    @Test("not-running target: writeFrame fails cleanly (no window to write)")
    func notRunningWriteFails() async {
        let adapter = AXWindowSystem(bundleID: "dev.ecn.apps.termtile.no-such-app")
        let ok = await adapter.writeFrame(12345, to: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(ok == false)
    }
}
