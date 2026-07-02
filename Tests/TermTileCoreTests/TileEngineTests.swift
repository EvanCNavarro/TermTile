import CoreGraphics
import Testing
@testable import TermTileCore

/// #10 — the pure retile POLICY (ADR-0001 rule 1). `TileEngine.retileCommands` maps the
/// tracked windows, in slot order, onto `TileLayout.frames`, emitting a `FrameCommand` only
/// where a window is NOT already at its target (idempotence — no feedback churn). Pure: no
/// clock, no AX, no pending-recording (the actor records pendings per AX write — #18/#19).
@Suite("TileEngine — pure retile policy")
struct TileEngineTests {
    // Non-zero gap + non-.zero visibleFrame origin so `.zero`-seeded windows are genuinely
    // off-target (else the idempotence filter silently empties the command list).
    let visible = CGRect(x: 100, y: 200, width: 1000, height: 800)
    let gap: CGFloat = 10
    let eps: CGFloat = 2.0

    func enabled() -> TileConfig { TileConfig(isEnabled: true, visibleFrame: visible, gap: gap) }

    /// N `.zero`-framed windows with ids 1...N.
    func windows(_ n: Int) -> [TrackedWindow] {
        (1...n).map { TrackedWindow(id: CGWindowID($0), frame: .zero) }
    }

    // 1 — off-target windows map to TileLayout slots, id-preserving, in slot order (N=1..4).
    @Test("retileCommands maps N windows to TileLayout slot order, ids preserved",
          arguments: [1, 2, 3, 4])
    func mapsToSlotOrder(n: Int) {
        let wins = windows(n)
        let cmds = TileEngine.retileCommands(windows: wins, config: enabled(), epsilon: eps)
        let frames = TileLayout.frames(count: n, visibleFrame: visible, gap: gap)
        #expect(cmds.count == n)
        for k in 0..<n {
            #expect(cmds[k].windowID == wins[k].id)
            #expect(cmds[k].targetFrame == frames[k])
        }
    }

    // 2 — disabled config emits nothing (off = inert).
    @Test("disabled config emits no commands")
    func disabledEmitsNothing() {
        let cfg = TileConfig(isEnabled: false, visibleFrame: visible, gap: gap)
        #expect(TileEngine.retileCommands(windows: windows(3), config: cfg, epsilon: eps).isEmpty)
    }

    // 3 — no windows → no commands (empty is not a retile).
    @Test("empty windows emits no commands")
    func emptyEmitsNothing() {
        #expect(TileEngine.retileCommands(windows: [], config: enabled(), epsilon: eps).isEmpty)
    }

    // 4 — idempotence: windows already AT their targets emit nothing.
    @Test("windows already at their targets emit no commands (idempotence)")
    func idempotentWhenOnGrid() {
        let frames = TileLayout.frames(count: 3, visibleFrame: visible, gap: gap)
        let onGrid = (0..<3).map { TrackedWindow(id: CGWindowID($0 + 1), frame: frames[$0]) }
        #expect(TileEngine.retileCommands(windows: onGrid, config: enabled(), epsilon: eps).isEmpty)
    }

    // 5 — partial: exactly one off-target window emits exactly one command, for that window.
    @Test("one off-target window emits exactly one command for it")
    func partialEmitsOnlyTheMover() {
        let frames = TileLayout.frames(count: 3, visibleFrame: visible, gap: gap)
        var wins = (0..<3).map { TrackedWindow(id: CGWindowID($0 + 1), frame: frames[$0]) }
        wins[1].frame = .zero  // knock window id 2 off its slot
        let cmds = TileEngine.retileCommands(windows: wins, config: enabled(), epsilon: eps)
        #expect(cmds.count == 1)
        #expect(cmds[0].windowID == 2)
        #expect(cmds[0].targetFrame == frames[1])
    }
}
