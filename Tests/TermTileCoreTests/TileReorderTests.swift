import CoreGraphics
import Testing
@testable import TermTileCore

/// #11 — the pure drag snap-reorder POLICY (ADR-0001 rule 1). `TileEngine.reorderCommands`
/// reassigns the dragged window to the slot whose CENTER is nearest its drop-point center,
/// shuffles the rest to fill (stable list remove+insert preserves relative order), and returns
/// the new slot order plus the `retileCommands` to snap everyone home. Pure: no clock, no AX,
/// no pending-recording (the actor records pendings per AX write — #18). Drag-END detection
/// (global mouse-up CGEventTap, spike-06) is the shell's job (#12), not Core's.
@Suite("TileEngine — drag snap-reorder policy (#11)")
struct TileReorderTests {
    // Non-zero gap + non-.zero origin so `.zero` frames are genuinely off-grid.
    let visible = CGRect(x: 100, y: 200, width: 1000, height: 800)
    let gap: CGFloat = 10
    let eps: CGFloat = 2.0

    func enabled() -> TileConfig { TileConfig(isEnabled: true, visibleFrame: visible, gap: gap) }
    func frames(_ n: Int) -> [CGRect] { TileLayout.frames(count: n, visibleFrame: visible, gap: gap) }

    /// N windows placed EXACTLY on their grid slots, ids 1...N (N1: exact frame, not just center).
    func onGrid(_ n: Int) -> [TrackedWindow] {
        let f = frames(n)
        return (0..<n).map { TrackedWindow(id: CGWindowID($0 + 1), frame: f[$0]) }
    }

    /// A 100×100 window whose CENTER sits on `slot`'s center — a drop point, NOT a grid frame.
    func droppedOn(_ slot: CGRect) -> CGRect {
        CGRect(x: slot.midX - 50, y: slot.midY - 50, width: 100, height: 100)
    }

    // KEYSTONE — drag id1 (slot 0) so its center lands on slot 3: id1 takes slot 3, the rest
    // shuffle up preserving relative order → [2,3,4,1]; the dragged window's snap targets slot 3.
    @Test("keystone: dragged window takes nearest-center slot, others shuffle to fill")
    func keystoneNearestSlot() {
        let f = frames(4)
        var wins = onGrid(4)
        wins[0].frame = droppedOn(f[3])
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps)
        #expect(order.map(\.id) == [2, 3, 4, 1])
        let dragCmd = cmds.first { $0.windowID == 1 }
        #expect(dragCmd?.targetFrame == f[3])
    }

    // Shuffle preserves the non-dragged windows' relative order (drag a middle window).
    @Test("shuffle preserves relative order of the non-dragged windows")
    func shufflePreservesOrder() {
        let f = frames(4)
        var wins = onGrid(4)
        wins[1].frame = droppedOn(f[3])                 // drag id2 (slot1) → slot3
        let (order, _) = TileEngine.reorderCommands(
            windows: wins, draggedID: 2, config: enabled(), epsilon: eps)
        #expect(order.map(\.id) == [1, 3, 4, 2])         // id2 → slot3; [1,3,4] relative order kept
    }

    // Idempotent: dragged window dropped EXACTLY on its own grid slot → order unchanged, no snap.
    @Test("dropped exactly on its own slot frame: order unchanged, no commands")
    func idempotentOnOwnSlot() {
        let wins = onGrid(4)                              // every window at its EXACT slot frame
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 3, config: enabled(), epsilon: eps)
        #expect(order.map(\.id) == [1, 2, 3, 4])
        #expect(cmds.isEmpty)
    }

    // Disabled config = inert: no reorder, no commands (spec "Off = no rigid behavior").
    @Test("disabled config: no reorder, no commands")
    func disabledNoop() {
        let f = frames(4)
        var wins = onGrid(4)
        wins[0].frame = droppedOn(f[3])
        let cfg = TileConfig(isEnabled: false, visibleFrame: visible, gap: gap)
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: cfg, epsilon: eps)
        #expect(order.map(\.id) == [1, 2, 3, 4])
        #expect(cmds.isEmpty)
    }

    // Untracked draggedID → no-op (leading guard, B1).
    @Test("untracked draggedID: no reorder, no commands")
    func untrackedNoop() {
        let wins = onGrid(4)
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 999, config: enabled(), epsilon: eps)
        #expect(order.map(\.id) == [1, 2, 3, 4])
        #expect(cmds.isEmpty)
    }

    // Empty windows → no crash (B1: leading guard runs before any TileLayout.frames/argmin).
    @Test("empty windows: no crash, no reorder")
    func emptyNoop() {
        let (order, cmds) = TileEngine.reorderCommands(
            windows: [], draggedID: 1, config: enabled(), epsilon: eps)
        #expect(order.isEmpty)
        #expect(cmds.isEmpty)
    }

    // Distance ties resolve to the LOWEST slot index (stable argmin, strict <). Drop id2 exactly
    // on the midpoint between slot0 and slot1 centers → it takes slot 0.
    @Test("distance tie resolves to lowest slot index")
    func tieLowestIndex() {
        let f = frames(2)
        var wins = onGrid(2)
        let midY = (f[0].midY + f[1].midY) / 2           // N=2: same x, midpoint in y
        wins[1].frame = CGRect(x: f[0].midX - 50, y: midY - 50, width: 100, height: 100)
        let (order, _) = TileEngine.reorderCommands(
            windows: wins, draggedID: 2, config: enabled(), epsilon: eps)
        #expect(order.map(\.id) == [2, 1])               // tie → slot0 (lowest index)
    }

    // N=1: a lone window dragged off its slot snaps back (identity reorder, one snap command).
    @Test("lone window dragged off its slot snaps back")
    func loneSnapBack() {
        let f = frames(1)
        var wins = onGrid(1)
        wins[0].frame = CGRect(x: 500, y: 500, width: 100, height: 100)
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps)
        #expect(order.map(\.id) == [1])
        #expect(cmds.count == 1)
        #expect(cmds[0].windowID == 1)
        #expect(cmds[0].targetFrame == f[0])
    }

    // PROPERTY (FL-6 multi-sample, N=2..8): dropping id1's center on the LAST slot's center makes
    // it the unique argmin → id1 lands at slot N-1, and the result is a PERMUTATION of the input
    // (no window lost or duplicated).
    @Test("property: result is a permutation; dragged lands at argmin-center slot",
          arguments: [2, 3, 4, 5, 6, 7, 8])
    func propertyPermutationAndArgmin(n: Int) {
        let f = frames(n)
        var wins = onGrid(n)
        wins[0].frame = droppedOn(f[n - 1])
        let (order, _) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps)
        #expect(order.count == n)
        #expect(Set(order.map(\.id)) == Set(wins.map(\.id)))
        #expect(order.firstIndex { $0.id == 1 } == n - 1)
    }
}
