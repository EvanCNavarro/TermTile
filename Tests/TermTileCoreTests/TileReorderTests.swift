import CoreGraphics
import Testing
@testable import TermTileCore

/// #11/#27 — the pure drag snap-reorder POLICY (ADR-0001 rule 1). `TileEngine.reorderCommands` takes
/// a FRESH enumerate (dragged window at its DROP position, others on their slots) + a `strategy`,
/// infers each window's slot via the shared nearest-slot model, and returns the new column-major slot
/// order + the `retileCommands`. Four strategies (see `ReorderStrategy`); each a pure permutation.
@Suite("TileEngine — drag reorder strategies (#11/#27)")
struct TileReorderTests {
    let visible = CGRect(x: 100, y: 200, width: 1000, height: 800)
    let gap: CGFloat = 10
    let eps: CGFloat = 2.0

    func enabled() -> TileConfig { TileConfig(isEnabled: true, visibleFrame: visible, gap: gap) }
    func frames(_ n: Int) -> [CGRect] { TileLayout.frames(count: n, visibleFrame: visible, gap: gap) }
    func onGrid(_ n: Int) -> [TrackedWindow] {
        let f = frames(n)
        return (0..<n).map { TrackedWindow(id: CGWindowID($0 + 1), frame: f[$0]) }
    }
    /// A 100×100 window centered on `slot` — a drop point, NOT a grid frame.
    func droppedOn(_ slot: CGRect) -> CGRect {
        CGRect(x: slot.midX - 50, y: slot.midY - 50, width: 100, height: 100)
    }
    /// Reorder: id1 (slot 0) dropped onto slot `target`, under `strategy`. Returns the new id order.
    func reorderIDs(n: Int, dropOn target: Int, _ strategy: ReorderStrategy) -> [CGWindowID] {
        var wins = onGrid(n)
        wins[0].frame = droppedOn(frames(n)[target])
        let (order, _) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps, strategy: strategy)
        return order.map(\.id)
    }

    // CANONICAL (audit table) — N=6 (3×2), drag id1 (top-left, s0) HORIZONTALLY onto s4 (top-right).
    // The four strategies give four DISTINCT column-major orders — the proof they're not aliases.
    @Test("N=6 horizontal drag s0→s4: swap trades only id1↔id5")
    func canonicalSwap() { #expect(reorderIDs(n: 6, dropOn: 4, .swap) == [5, 2, 3, 4, 1, 6]) }

    @Test("N=6 horizontal drag s0→s4: columnShift snakes column-major (the diagonal wrap)")
    func canonicalColumnShift() { #expect(reorderIDs(n: 6, dropOn: 4, .columnShift) == [2, 3, 4, 5, 1, 6]) }

    @Test("N=6 horizontal drag s0→s4: rowShift shifts the top row, bottom row (2,4,6) frozen")
    func canonicalRowShift() {
        let order = reorderIDs(n: 6, dropOn: 4, .rowShift)
        #expect(order == [3, 2, 5, 4, 1, 6])
        #expect([order[1], order[3], order[5]] == [2, 4, 6])   // bottom row (s1,s3,s5) untouched
    }

    // ADAPTIVE follows drag direction: a horizontal drag (s0→s4) resolves to rowShift…
    @Test("adaptive: horizontal drag resolves to rowShift")
    func adaptiveHorizontal() { #expect(reorderIDs(n: 6, dropOn: 4, .adaptive) == [3, 2, 5, 4, 1, 6]) }

    // …and a vertical drag (s0→s1, same column) resolves to columnShift.
    @Test("adaptive: vertical drag resolves to columnShift")
    func adaptiveVertical() {
        #expect(reorderIDs(n: 6, dropOn: 1, .adaptive) == reorderIDs(n: 6, dropOn: 1, .columnShift))
        #expect(reorderIDs(n: 6, dropOn: 1, .adaptive) == [2, 1, 3, 4, 5, 6])
    }

    // NO-OP guard (all strategies): dropped nearest its OWN origin slot → identity, no commands.
    @Test("dropped on its own slot: identity order, no commands", arguments: ReorderStrategy.allCases)
    func noOpOnOwnSlot(strategy: ReorderStrategy) {
        let wins = onGrid(4)                       // every window EXACTLY on its slot
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 3, config: enabled(), epsilon: eps, strategy: strategy)
        #expect(order.map(\.id) == [1, 2, 3, 4])
        #expect(cmds.isEmpty)
    }

    // LONE-LAST (odd N): swap id1 (s0, half-height) with id5 (s4, the lone FULL-height slot). id1 must
    // land on the full-height frame, id5 on id1's old half slot — sizes follow the final slot index.
    @Test("lone-last: swap into the full-height slot resizes correctly")
    func loneLastSwap() {
        var wins = onGrid(5)
        let f = frames(5)
        wins[0].frame = droppedOn(f[4])            // drag id1 onto the lone full-height slot
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps, strategy: .swap)
        #expect(order.map(\.id) == [5, 2, 3, 4, 1])
        #expect(cmds.first { $0.windowID == 1 }?.targetFrame == f[4])   // id1 → full-height slot
        #expect(cmds.first { $0.windowID == 5 }?.targetFrame == f[0])   // id5 → id1's old half slot
    }

    // Disabled / untracked / empty → no reorder, no commands (leading guards, B1).
    @Test("disabled config: no reorder, no commands")
    func disabledNoop() {
        var wins = onGrid(4)
        wins[0].frame = droppedOn(frames(4)[3])
        let cfg = TileConfig(isEnabled: false, visibleFrame: visible, gap: gap)
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: cfg, epsilon: eps, strategy: .swap)
        #expect(order.map(\.id) == [1, 2, 3, 4])
        #expect(cmds.isEmpty)
    }

    @Test("untracked draggedID / empty windows: no crash, no reorder")
    func untrackedAndEmptyNoop() {
        let (o1, c1) = TileEngine.reorderCommands(
            windows: onGrid(4), draggedID: 999, config: enabled(), epsilon: eps, strategy: .swap)
        #expect(o1.map(\.id) == [1, 2, 3, 4]); #expect(c1.isEmpty)
        let (o2, c2) = TileEngine.reorderCommands(
            windows: [], draggedID: 1, config: enabled(), epsilon: eps, strategy: .swap)
        #expect(o2.isEmpty); #expect(c2.isEmpty)
    }

    // PROPERTY (N=2..8, every strategy): the result is always a PERMUTATION (no window lost/dup) and
    // the dragged window lands on the argmin slot it was dropped on (its center → last slot here).
    @Test("property: permutation + dragged lands at drop slot",
          arguments: [2, 3, 4, 5, 6, 7, 8], ReorderStrategy.allCases)
    func propertyPermutation(n: Int, strategy: ReorderStrategy) {
        let order = reorderIDs(n: n, dropOn: n - 1, strategy)
        #expect(order.count == n)
        #expect(Set(order) == Set((1...n).map(CGWindowID.init)))
        #expect(order.firstIndex(of: 1) == n - 1)   // id1 dropped on the last slot → lands there
    }

    // ── Edge-case hardening (#27) ────────────────────────────────────────────────────────────────

    // N=1: a lone window dragged off its slot snaps back — the no-op path (target==vacated==0), all
    // strategies. Was NOT covered (existing tests are N≥2).
    @Test("N=1: lone window dragged off snaps back (all strategies)", arguments: ReorderStrategy.allCases)
    func n1SnapBack(strategy: ReorderStrategy) {
        var wins = onGrid(1)
        wins[0].frame = CGRect(x: 500, y: 500, width: 100, height: 100)
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps, strategy: strategy)
        #expect(order.map(\.id) == [1])
        #expect(cmds == [FrameCommand(windowID: 1, targetFrame: frames(1)[0])])
    }

    // N=2 (1 column, 2 rows): only two arrangements exist → ALL FOUR strategies must coincide.
    @Test("N=2: all four strategies coincide")
    func n2AllCoincide() {
        var wins = onGrid(2)
        wins[0].frame = droppedOn(frames(2)[1])            // drag id1 → slot 1
        let orders = ReorderStrategy.allCases.map { s in
            TileEngine.reorderCommands(windows: wins, draggedID: 1, config: enabled(),
                                       epsilon: eps, strategy: s).windows.map(\.id)
        }
        #expect(orders.allSatisfy { $0 == [2, 1] })
    }

    // Dragging a MIDDLE window (not id1): the shared model must infer occupant/vacated for ANY id.
    // Drag id3 (slot 2) onto slot 0 → swap id3↔id1; ids 2,4 stay.
    @Test("middle-window drag: shared model handles any dragged id")
    func middleWindowDrag() {
        var wins = onGrid(4)
        wins[2].frame = droppedOn(frames(4)[0])            // drag id3 (slot 2) onto slot 0
        let (order, _) = TileEngine.reorderCommands(
            windows: wins, draggedID: 3, config: enabled(), epsilon: eps, strategy: .swap)
        #expect(order.map(\.id) == [3, 2, 1, 4])           // id3→s0, id1→s2
    }

    // CROSS-ROW + cross-column drag (id1 top-left → s5 bottom-right): every strategy must stay a
    // valid bijection (no window lost/duplicated, no crash) with the dragged window at the drop slot.
    @Test("cross-row drag stays a valid permutation (all strategies)", arguments: ReorderStrategy.allCases)
    func crossRowPermutation(strategy: ReorderStrategy) {
        var wins = onGrid(6)
        wins[0].frame = droppedOn(frames(6)[5])
        let (order, _) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps, strategy: strategy)
        #expect(Set(order.map(\.id)) == Set((1...6).map(CGWindowID.init)))   // bijection
        #expect(order.firstIndex { $0.id == 1 } == 5)                        // dragged → drop slot
    }

    // UNTILED input (all windows overlapping → >1 slot maps empty): must NOT crash on a force-unwrap;
    // degrades to a plain grid snap (a permutation tiled to the grid).
    @Test("untiled/overlapping windows: degrades to a grid snap, no crash")
    func untiledFallback() {
        let overlap = CGRect(x: 0, y: 0, width: 100, height: 100)
        let wins = (1...3).map { TrackedWindow(id: CGWindowID($0), frame: overlap) }
        let (order, cmds) = TileEngine.reorderCommands(
            windows: wins, draggedID: 1, config: enabled(), epsilon: eps, strategy: .swap)
        #expect(Set(order.map(\.id)) == Set([1, 2, 3]))    // no window lost, no crash
        let f = frames(3)
        #expect(cmds.count == 3)                            // all snapped onto the grid
        for cmd in cmds { #expect([f[0], f[1], f[2]].contains(cmd.targetFrame)) }
    }

    // ADAPTIVE on a diagonal drag: DETERMINISTIC + a valid permutation. With these wide slots
    // (485w > 385h) a top-left→bottom-right drag has |dx|>|dy| → resolves to rowShift.
    @Test("adaptive diagonal drag: deterministic; resolves by aspect ratio")
    func adaptiveDiagonal() {
        var wins = onGrid(4)
        wins[0].frame = droppedOn(frames(4)[3])            // s0 → s3 (diagonal)
        func run(_ s: ReorderStrategy) -> [CGWindowID] {
            TileEngine.reorderCommands(windows: wins, draggedID: 1, config: enabled(),
                                       epsilon: eps, strategy: s).windows.map(\.id)
        }
        #expect(run(.adaptive) == run(.adaptive))          // deterministic
        #expect(Set(run(.adaptive)) == Set([1, 2, 3, 4]))  // valid permutation
        #expect(run(.adaptive) == run(.rowShift))          // wide slots → horizontal wins
    }
}
