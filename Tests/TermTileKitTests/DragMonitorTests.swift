import CoreGraphics
import Foundation
import Testing
@testable import TermTileKit
import TermTileCore

/// #14b — the drag-reorder decision logic of `DragMonitor`, exercised WITHOUT a real `CGEventTap`
/// (the tap plumbing is a live-only surface proven by AXProbe `dragcheck`). `handleDown`/`handleUp`
/// are the pure-ish seam: identity is captured at mouse-DOWN (skeptic B1) and the click-vs-drag
/// gate lives at mouse-UP (skeptic B2 — a click must NOT reorder). Injected closures stand in for
/// the actor so the gate + identity plumbing is provable at unit level.
@Suite("DragMonitor — click-vs-drag gate + down-identity")
struct DragMonitorTests {
    // A real drag: DOWN inside a window (resolves to its id), UP far away (travel > threshold) →
    // fires onDragEnd with the DOWN id (skeptic B1: identity is the down window, not the drop).
    @Test("a real drag (travel > threshold) fires onDragEnd with the id resolved at DOWN")
    func realDragFiresWithDownID() async {
        let firedID = Locked<CGWindowID?>(nil)
        let original = CGRect(x: 0, y: 0, width: 100, height: 100)
        let monitor = DragMonitor(
            travelThreshold: 6,
            resolveWindow: { point in
                point.x < 100 ? TrackedWindow(id: 42, frame: original) : nil
            },
            currentFrame: { _ in CGRect(x: 400, y: 400, width: 100, height: 100) },
            onDragEnd: { id in firedID.set(id) })

        monitor.handleDown(at: CGPoint(x: 10, y: 10))               // inside window 42
        let fired = await monitor.handleUp(at: CGPoint(x: 500, y: 500))   // dropped elsewhere (far)

        #expect(fired == 42)                                        // the DOWN id, not the drop point's
        #expect(firedID.get() == 42)
    }

    // A plain click (zero travel) must NOT fire — otherwise every click inside a managed window is a
    // reorder trigger (skeptic B2).
    @Test("a click (travel below threshold) fires nothing")
    func clickFiresNothing() async {
        let firedID = Locked<CGWindowID?>(nil)
        let monitor = DragMonitor(
            travelThreshold: 6,
            resolveWindow: { _ in TrackedWindow(id: 42, frame: CGRect(x: 0, y: 0, width: 100, height: 100)) },
            currentFrame: { _ in nil },
            onDragEnd: { id in firedID.set(id) })

        monitor.handleDown(at: CGPoint(x: 10, y: 10))
        let fired = await monitor.handleUp(at: CGPoint(x: 12, y: 11))   // 2.2px travel < 6

        #expect(fired == nil)
        #expect(firedID.get() == nil)
    }

    // A drag that STARTS over no managed window (down id nil) fires nothing even past the threshold.
    @Test("a drag starting over no window fires nothing (down id nil)")
    func dragOverNothingFiresNothing() async {
        let fired = Locked<Bool>(false)
        let monitor = DragMonitor(
            travelThreshold: 6,
            resolveWindow: { _ in nil },                            // down over a gap
            currentFrame: { _ in nil },
            onDragEnd: { _ in fired.set(true) })

        monitor.handleDown(at: CGPoint(x: 999, y: 999))
        let out = await monitor.handleUp(at: CGPoint(x: 200, y: 200))

        #expect(out == nil)
        #expect(fired.get() == false)
    }

    // The screenshot/text-selection case: pointer travelled, but the managed window itself did not
    // move. This must NOT snap a maximized/focused terminal back to the grid.
    @Test("a pointer drag over an unchanged window fires nothing")
    func unchangedWindowDragFiresNothing() async {
        let firedID = Locked<CGWindowID?>(nil)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let monitor = DragMonitor(
            travelThreshold: 6,
            resolveWindow: { _ in TrackedWindow(id: 42, frame: frame) },
            currentFrame: { _ in frame },
            onDragEnd: { id in firedID.set(id) })

        monitor.handleDown(at: CGPoint(x: 10, y: 10))
        let fired = await monitor.handleUp(at: CGPoint(x: 500, y: 500))

        #expect(fired == nil)
        #expect(firedID.get() == nil)
    }

    // A title-bar double-click zoom/restore can change the window's frame without being a window
    // drag. Even with small pointer jitter beyond the travel threshold, drag-reorder must not treat
    // a resize/zoom as a drop and snap the window into a new grid slot.
    @Test("a zoom or resize gesture does not fire drag reorder")
    func zoomOrResizeGestureFiresNothing() async {
        let firedID = Locked<CGWindowID?>(nil)
        let original = CGRect(x: 120, y: 100, width: 420, height: 300)
        let zoomed = CGRect(x: 40, y: 20, width: 1200, height: 800)
        let monitor = DragMonitor(
            travelThreshold: 6,
            resolveWindow: { _ in TrackedWindow(id: 42, frame: original) },
            currentFrame: { _ in zoomed },
            onDragEnd: { id in firedID.set(id) })

        monitor.handleDown(at: CGPoint(x: 200, y: 120))
        let fired = await monitor.handleUp(at: CGPoint(x: 208, y: 127))

        #expect(fired == nil)
        #expect(firedID.get() == nil)
    }
}

/// Tiny lock-guarded box so the @Sendable closures can record across the actor hop without a data race.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ initial: T) { value = initial }
    func set(_ v: T) { lock.withLock { value = v } }
    func get() -> T { lock.withLock { value } }
}
