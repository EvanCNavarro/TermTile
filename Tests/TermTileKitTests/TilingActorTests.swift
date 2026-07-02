import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// #18 — the Kit-layer orchestration (ADR-0001 rules 2 & 4): the `WindowSystem` port + fake +
/// `TilingActor`, proven against the in-memory fake (no live AX — that is #19). The actor wires
/// the PURE `WindowStateReducer`/`TileEngine`, applies emitted `[FrameCommand]` via the port,
/// and records ONE `PendingMove` per AX WRITE (size→pos→size trio) so its own write echoes
/// classify `.internal` (the feedback-loop break). Clock/TTL are actor-side; tests pass a large
/// `ttlSeconds` so ms-scale timing never expires a pending mid-test.
@Suite("TilingActor")
struct TilingActorTests {
    // Keystone geometry: visibleFrame (0,0,1000,1000), gap 10 → known slot targets.
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let gap: CGFloat = 10
    let eps: CGFloat = 2
    func enabled() -> TileConfig { TileConfig(isEnabled: true, visibleFrame: visible, gap: gap) }
    func targets(_ n: Int) -> [CGRect] { TileLayout.frames(count: n, visibleFrame: visible, gap: gap) }
    func win(_ id: CGWindowID, _ r: CGRect) -> TrackedWindow { TrackedWindow(id: id, frame: r) }
    func off(_ id: CGWindowID) -> TrackedWindow { win(id, CGRect(x: 0, y: 0, width: 100, height: 100)) }

    // KEYSTONE — activate tiles all off-grid windows; their size→pos→size echoes classify
    // internal, drain the ledger to empty, and cause ZERO further writes (ADR rule 3 loop break).
    @Test("keystone: activate tiles all; echoes classify internal; ledger drains; no re-write")
    func keystoneActivateEchoesDrain() async {
        let seed = [off(1), off(2), off(3)]
        let fake = InMemoryWindowSystem(windows: seed)
        let actor = TilingActor(system: fake, epsilon: eps, ttlSeconds: 100)
        let t = targets(3)
        // R3: each seed is genuinely off its OWN slot target → 3 writes are provable.
        for k in 0..<3 { #expect(seed[k].frame != t[k]) }

        await actor.activate(config: enabled())

        let writes = await fake.recordedWrites
        #expect(writes.count == 3)
        #expect(Set(writes.map(\.id)) == Set([1, 2, 3]))
        for w in writes { #expect(w.target == t[Int(w.id) - 1]) }

        // 3 pendings per window (size→pos→size trio) = 9.
        #expect(await actor.snapshot.pending.count == 9)

        // Replay each window's 3 echoes: size1 = (target.size, cachedOrigin), pos + size2 = target.
        for id in [CGWindowID(1), 2, 3] {
            let target = t[Int(id) - 1]
            let sizedOld = CGRect(origin: CGPoint(x: 0, y: 0), size: target.size)
            await actor.handle(WindowEvent(windowID: id, kind: .resized, frame: sizedOld))
            await actor.handle(WindowEvent(windowID: id, kind: .moved, frame: target))
            await actor.handle(WindowEvent(windowID: id, kind: .resized, frame: target))
        }

        #expect(await actor.snapshot.pending.isEmpty)      // all echoes internal → drained
        #expect(await fake.recordedWrites.count == 3)       // internal echoes never retile
    }

    // Disabled config = inert: no writes even over off-grid windows (spec: "Off = no rigid behavior").
    @Test("disabled config: activate issues no writes")
    func disabledInert() async {
        let fake = InMemoryWindowSystem(windows: [off(1), off(2)])
        let actor = TilingActor(system: fake, epsilon: eps, ttlSeconds: 100)
        await actor.activate(config: TileConfig(isEnabled: false, visibleFrame: visible, gap: gap))
        #expect(await fake.recordedWrites.isEmpty)
        #expect(await actor.snapshot.pending.isEmpty)
    }

    // An external move (frame far from any pending) does NOT drain the ledger and issues no
    // writes — proves internal≠external discrimination at the actor boundary (drag-reorder = #11).
    @Test("external move does not drain the ledger and issues no writes")
    func externalMoveNoDrain() async {
        let fake = InMemoryWindowSystem(windows: [off(1), off(2), off(3)])
        let actor = TilingActor(system: fake, epsilon: eps, ttlSeconds: 100)
        await actor.activate(config: enabled())
        #expect(await actor.snapshot.pending.count == 9)

        await actor.handle(WindowEvent(windowID: 1, kind: .moved,
                                       frame: CGRect(x: 900, y: 900, width: 485, height: 485)))
        #expect(await actor.snapshot.pending.count == 9)    // no pending consumed
        #expect(await fake.recordedWrites.count == 3)        // no retile on a drag
    }

    // A created new window while enabled retiles the CHANGED set. Adding id4 to 3 on-grid windows
    // retargets id3 (lone-last full-height → half-height) AND places id4 → TWO writes (audit R2).
    @Test("created new window retiles the changed set (id3 retargeted + id4)")
    func createdRetilesChangedSet() async {
        let t3 = targets(3)
        let seed = [win(1, t3[0]), win(2, t3[1]), win(3, t3[2])]   // already on their count=3 grid
        let fake = InMemoryWindowSystem(windows: seed)
        let actor = TilingActor(system: fake, epsilon: eps, ttlSeconds: 100)
        await actor.activate(config: enabled())
        #expect(await fake.recordedWrites.isEmpty)             // already on grid → idempotent, no writes

        await actor.handle(WindowEvent(windowID: 4, kind: .created,
                                       frame: CGRect(x: 0, y: 0, width: 50, height: 50)))
        let t4 = targets(4)
        let writes = await fake.recordedWrites
        #expect(Set(writes.map(\.id)) == Set([3, 4]))          // id1/id2 invariant 3→4, stay silent
        let byID = Dictionary(uniqueKeysWithValues: writes.map { ($0.id, $0.target) })
        #expect(byID[3] == t4[2])                              // id3 full→half height
        #expect(byID[4] == t4[3])
        #expect(t4[2].height != t3[2].height)                  // sanity: the retarget is real
    }

    // snapshot is an instant read reflecting the cached state (no AX round-trip semantics).
    @Test("snapshot reflects the cached state after activate")
    func snapshotReflectsCache() async {
        let fake = InMemoryWindowSystem(windows: [off(1), off(2)])
        let actor = TilingActor(system: fake, epsilon: eps, ttlSeconds: 100)
        await actor.activate(config: enabled())
        #expect(await actor.snapshot.windows.map(\.id) == [1, 2])
    }

    // run() consumes the port's event stream (ADR rule 4, actor side). Finishable stream + a
    // real sync point (await the task) avoid flake/hang (audit R4).
    @Test("run() consumes the event stream")
    func runConsumesStream() async {
        let fake = InMemoryWindowSystem(windows: [])
        let actor = TilingActor(system: fake, epsilon: eps, ttlSeconds: 100)
        await actor.activate(config: enabled())               // empty seed → no writes yet
        let task = Task { await actor.run() }
        await fake.emit(WindowEvent(windowID: 5, kind: .created,
                                    frame: CGRect(x: 0, y: 0, width: 50, height: 50)))
        await fake.finish()
        await task.value                                       // run() returns when the stream ends
        #expect(await actor.snapshot.windows.contains { $0.id == 5 })
        #expect(await fake.recordedWrites.count == 1)          // the created window was tiled
    }

    // Fake conformance sanity: enumerate/read return the seed; unknown id reads nil.
    @Test("fake returns seeded windows and frames")
    func fakeConformance() async {
        let w = off(1)
        let fake = InMemoryWindowSystem(windows: [w])
        #expect(await fake.tileableWindows() == [w])
        #expect(await fake.readFrame(1) == w.frame)
        #expect(await fake.readFrame(99) == nil)
    }
}
