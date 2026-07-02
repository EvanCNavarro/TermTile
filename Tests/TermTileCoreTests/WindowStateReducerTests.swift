import CoreGraphics
import Testing
@testable import TermTileCore

/// #9 — the pure window state model: reducer + expectation ledger (ADR-0001 rules 3-4,
/// Core half). Classification API (`MoveClassifier`/`PendingMove`) landed in #6; this suite
/// proves the reducer folds events into `WindowState`, registers/consumes ledger entries,
/// and tolerates the spike-05 destroy anomalies. All pure: `nowEpoch`/`epsilon` are params.
@Suite("WindowStateReducer")
struct WindowStateReducerTests {
    // Shared fixtures.
    let eps: CGFloat = 2.0
    let now: Double = 1_000.0
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 100, _ h: CGFloat = 80) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
    func reduce(_ s: WindowState, _ e: WindowEvent) -> (WindowState, [FrameCommand]) {
        WindowStateReducer.reduce(s, e, nowEpoch: now, epsilon: eps)
    }

    // 1 — created adds a new tracked window with its frame.
    @Test("created adds a new tracked window")
    func createdAdds() {
        let (s, cmds) = reduce(WindowState(), WindowEvent(windowID: 7, kind: .created, frame: rect(0, 0)))
        #expect(s.windows == [TrackedWindow(id: 7, frame: rect(0, 0))])
        #expect(cmds.isEmpty)
    }

    // 2 — created for an existing id updates the frame in place, no duplicate.
    @Test("created for existing id updates frame, no duplicate")
    func createdExistingUpdates() {
        var s = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .created, frame: rect(9, 9)))
        #expect(s.windows == [TrackedWindow(id: 7, frame: rect(9, 9))])
    }

    // 3 — destroyed removes the window.
    @Test("destroyed removes the window")
    func destroyedRemoves() {
        var s = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0)),
                                      TrackedWindow(id: 8, frame: rect(1, 1))])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .destroyed, frame: nil))
        #expect(s.windows == [TrackedWindow(id: 8, frame: rect(1, 1))])
    }

    // 4 — destroyed drops that window's pending ledger entries.
    @Test("destroyed drops its pending ledger entries")
    func destroyedDropsPendings() {
        var s = WindowState(
            windows: [TrackedWindow(id: 7, frame: rect(0, 0))],
            pending: [PendingMove(windowID: 7, expectedFrame: rect(5, 5), expiresAtEpoch: now + 1),
                      PendingMove(windowID: 8, expectedFrame: rect(6, 6), expiresAtEpoch: now + 1)])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .destroyed, frame: nil))
        #expect(s.pending == [PendingMove(windowID: 8, expectedFrame: rect(6, 6), expiresAtEpoch: now + 1)])
    }

    // 5 — destroyed of an UNKNOWN id leaves state unchanged (spike-05 ~5s undo-close anomaly).
    @Test("destroyed of an unknown id leaves state unchanged")
    func destroyedUnknownNoop() {
        let start = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))])
        let (s, cmds) = reduce(start, WindowEvent(windowID: 999, kind: .destroyed, frame: nil))
        #expect(s == start)
        #expect(cmds.isEmpty)
    }

    // 6 — moved matching a live pending → internal: pending consumed, frame updated.
    @Test("moved matching a live pending is internal, consumes pending, updates frame")
    func movedInternalConsumes() {
        var s = WindowState(
            windows: [TrackedWindow(id: 7, frame: rect(0, 0))],
            pending: [PendingMove(windowID: 7, expectedFrame: rect(50, 50), expiresAtEpoch: now + 1)])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .moved, frame: rect(51, 49)))  // within eps=2
        #expect(s.windows == [TrackedWindow(id: 7, frame: rect(51, 49))])
        #expect(s.pending.isEmpty)
    }

    // 7 — moved with a live NON-matching pending → external: frame updated, pending SURVIVES (R3).
    @Test("moved with a live non-matching pending is external and preserves the pending")
    func movedExternalPreservesPending() {
        let live = PendingMove(windowID: 7, expectedFrame: rect(50, 50), expiresAtEpoch: now + 1)
        var s = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))], pending: [live])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .moved, frame: rect(300, 300)))  // far from expected
        #expect(s.windows == [TrackedWindow(id: 7, frame: rect(300, 300))])
        #expect(s.pending == [live])  // external move must NOT consume an unmatched pending
    }

    // R2 — multi-pending same window: echo matches B, so B is consumed and A survives.
    @Test("consume removes the frame-matched pending, not the first for the window")
    func consumeByFrameMatch() {
        let a = PendingMove(windowID: 7, expectedFrame: rect(10, 10), expiresAtEpoch: now + 1)
        let b = PendingMove(windowID: 7, expectedFrame: rect(200, 200), expiresAtEpoch: now + 1)
        var s = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))], pending: [a, b])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .moved, frame: rect(201, 199)))  // matches B
        #expect(s.pending == [a])  // A (position pending) must survive; only B consumed
    }

    // 8 — expired pendings are GC'd on any reduce step (bounded ledger).
    @Test("expired pendings are garbage-collected on any reduce")
    func expiredPendingsGCd() {
        var s = WindowState(
            windows: [TrackedWindow(id: 7, frame: rect(0, 0))],
            pending: [PendingMove(windowID: 7, expectedFrame: rect(5, 5), expiresAtEpoch: now - 1)])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .created, frame: rect(0, 0)))
        #expect(s.pending.isEmpty)  // expired entry removed even on an unrelated event
    }

    // 9 — resized echo matching a pending → internal (the size→pos→size echo is a resized).
    @Test("resized echo matching a pending is internal and consumes it")
    func resizedInternalConsumes() {
        var s = WindowState(
            windows: [TrackedWindow(id: 7, frame: rect(0, 0))],
            pending: [PendingMove(windowID: 7, expectedFrame: rect(50, 50, 200, 150), expiresAtEpoch: now + 1)])
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .resized, frame: rect(50, 50, 200, 150)))
        #expect(s.pending.isEmpty)
    }

    // 10 — recording appends one pending per command with correct fields.
    @Test("recording appends one pending per command")
    func recordingAppends() {
        let cmds = [FrameCommand(windowID: 7, targetFrame: rect(1, 1)),
                    FrameCommand(windowID: 8, targetFrame: rect(2, 2))]
        let s = WindowState().recording(commands: cmds, expiresAtEpoch: now + 5)
        #expect(s.pending == [
            PendingMove(windowID: 7, expectedFrame: rect(1, 1), expiresAtEpoch: now + 5),
            PendingMove(windowID: 8, expectedFrame: rect(2, 2), expiresAtEpoch: now + 5),
        ])
    }

    // 11 — proof of absence: reduce emits NO commands for any event kind (#9 has no tiling policy;
    //      command emission is #10/#11's reducer cases).
    @Test("reduce emits no FrameCommands for any event kind",
          arguments: [WindowEventKind.created, .moved, .resized, .destroyed])
    func reduceEmitsNoCommands(kind: WindowEventKind) {
        let frame: CGRect? = kind == .destroyed ? nil : rect(0, 0)
        let s = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))])
        let (_, cmds) = reduce(s, WindowEvent(windowID: 7, kind: kind, frame: frame))
        #expect(cmds.isEmpty)
    }

    // 12 — KEYSTONE: rule-3 round trip. Record 2 commands → 2 echoes drain the ledger; a 3rd
    //      non-matching move stays external. Written first; carries the classification burden.
    @Test("keystone: recording N commands then N echoes drains the ledger, 3rd stays external")
    func keystoneRoundTrip() {
        let c1 = FrameCommand(windowID: 7, targetFrame: rect(10, 10))
        let c2 = FrameCommand(windowID: 8, targetFrame: rect(20, 20))
        var s = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0)),
                                      TrackedWindow(id: 8, frame: rect(1, 1))])
            .recording(commands: [c1, c2], expiresAtEpoch: now + 1)
        #expect(s.pending.count == 2)
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .moved, frame: rect(11, 9)))   // echo c1
        (s, _) = reduce(s, WindowEvent(windowID: 8, kind: .resized, frame: rect(20, 20))) // echo c2
        #expect(s.pending.isEmpty)  // both echoes consumed → ledger drained
        // 3rd move matches no pending → external, no ledger churn, no phantom.
        (s, _) = reduce(s, WindowEvent(windowID: 7, kind: .moved, frame: rect(500, 500)))
        #expect(s.pending.isEmpty)
        #expect(s.windows.count == 2)
    }

    // 13 — moved/resized for an UNKNOWN id → no phantom window, state unchanged (anomaly guard).
    @Test("moved/resized for an unknown id creates no phantom window",
          arguments: [WindowEventKind.moved, .resized])
    func movedUnknownNoPhantom(kind: WindowEventKind) {
        let start = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))])
        let (s, _) = reduce(start, WindowEvent(windowID: 404, kind: kind, frame: rect(9, 9)))
        #expect(s == start)
    }

    // 14 — nil frame on a frame-bearing kind → defensive no-op (malformed event).
    @Test("nil frame on created/moved/resized is a defensive no-op",
          arguments: [WindowEventKind.created, .moved, .resized])
    func nilFrameNoop(kind: WindowEventKind) {
        let start = WindowState(windows: [TrackedWindow(id: 7, frame: rect(0, 0))])
        let (s, cmds) = reduce(start, WindowEvent(windowID: 7, kind: kind, frame: nil))
        #expect(s == start)
        #expect(cmds.isEmpty)
    }

    // ── #10: config-driven retile emission (ADR-0001 rule 1). Reduce emits commands on an
    //    actual window-set CHANGE when enabled; it records NO pendings (the actor does that
    //    per AX write — #18/#19). visible/gap chosen so `.zero`-seeded windows are off-target.
    let visible = CGRect(x: 100, y: 200, width: 1000, height: 800)
    let gap: CGFloat = 10
    func enabled() -> TileConfig { TileConfig(isEnabled: true, visibleFrame: visible, gap: gap) }
    func reduceCfg(_ s: WindowState, _ e: WindowEvent, _ cfg: TileConfig)
        -> (WindowState, [FrameCommand]) {
        WindowStateReducer.reduce(s, e, nowEpoch: now, epsilon: eps, config: cfg)
    }

    // 15 — created a NEW window (enabled) retiles ALL tracked windows; records no pendings.
    @Test("created new window with enabled config retiles all tracked, records no pending")
    func createdEnabledRetilesAll() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero),
                                       TrackedWindow(id: 2, frame: .zero)])
        let (s, cmds) = reduceCfg(s0, WindowEvent(windowID: 3, kind: .created, frame: rect(0, 0)), enabled())
        let frames = TileLayout.frames(count: 3, visibleFrame: visible, gap: gap)
        #expect(cmds.count == 3)
        #expect(cmds.map { $0.targetFrame } == frames)
        #expect(s.pending.isEmpty)  // reduce records nothing — the actor records per AX write
        #expect(s.windows.count == 3)
    }

    // 16 — created for an EXISTING id is a frame update, NOT a set change → no retile (R2).
    @Test("created for existing id with enabled config does not retile")
    func createdExistingEnabledNoRetile() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero)])
        let (_, cmds) = reduceCfg(s0, WindowEvent(windowID: 1, kind: .created, frame: rect(9, 9)), enabled())
        #expect(cmds.isEmpty)
    }

    // 17 — destroyed a KNOWN id (enabled) retiles the remainder.
    @Test("destroyed known id with enabled config retiles the remainder")
    func destroyedEnabledRetilesRemainder() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero),
                                       TrackedWindow(id: 2, frame: .zero),
                                       TrackedWindow(id: 3, frame: .zero)])
        let (_, cmds) = reduceCfg(s0, WindowEvent(windowID: 3, kind: .destroyed, frame: nil), enabled())
        #expect(cmds.count == 2)
        #expect(cmds.map { $0.targetFrame } == TileLayout.frames(count: 2, visibleFrame: visible, gap: gap))
    }

    // 18 — destroyed an UNKNOWN id (enabled) is a spike-05 phantom → set unchanged → no retile (R2).
    @Test("destroyed unknown id with enabled config does not retile")
    func destroyedUnknownEnabledNoRetile() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero)])
        let (_, cmds) = reduceCfg(s0, WindowEvent(windowID: 999, kind: .destroyed, frame: nil), enabled())
        #expect(cmds.isEmpty)
    }

    // 19 — nil-frame created (enabled) is a defensive no-op → set unchanged → no retile (R2).
    @Test("nil-frame created with enabled config does not retile")
    func nilFrameCreatedEnabledNoRetile() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero)])
        let (_, cmds) = reduceCfg(s0, WindowEvent(windowID: 2, kind: .created, frame: nil), enabled())
        #expect(cmds.isEmpty)
    }

    // 20 — moved (enabled) never retiles — drag reorder is #11, not the structural engine.
    @Test("moved with enabled config emits no commands (drag reorder is #11)")
    func movedEnabledNoRetile() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero),
                                       TrackedWindow(id: 2, frame: .zero)])
        let (_, cmds) = reduceCfg(s0, WindowEvent(windowID: 1, kind: .moved, frame: rect(5, 5)), enabled())
        #expect(cmds.isEmpty)
    }

    // 21 — regression: created new window with DISABLED config emits nothing (off = inert).
    @Test("created new window with disabled config emits no commands")
    func createdDisabledNoRetile() {
        let s0 = WindowState(windows: [TrackedWindow(id: 1, frame: .zero)])
        let (_, cmds) = reduceCfg(s0, WindowEvent(windowID: 2, kind: .created, frame: rect(0, 0)),
                                  TileConfig(isEnabled: false, visibleFrame: visible, gap: gap))
        #expect(cmds.isEmpty)
    }
}
