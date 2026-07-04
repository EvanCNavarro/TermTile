import CoreGraphics
import Testing
@testable import TermTileKit
import TermTileCore

/// #18 — the Kit-layer orchestration (ADR-0001 rules 2 & 4): the `WindowSystem` port + fake +
/// `TilingActor`, proven against the in-memory fake (no live AX — that is #19). TermTile is a
/// MANUAL / ON-DEMAND tiler: each action enumerates windows FRESH via the port, tiles/reorders,
/// and writes. No cached model / event stream (cut once on-demand drag-reorder #26 superseded it).
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

    // KEYSTONE — activate enumerates the target's windows FRESH and tiles all off-grid ones to their
    // slots. The flip that reddens it: activate(.disabled) → zero writes.
    @Test("keystone: activate tiles all fresh-enumerated windows to their grid slots")
    func keystoneActivateTilesToGrid() async {
        let seed = [off(1), off(2), off(3)]
        let fake = InMemoryWindowSystem(windows: seed)
        let actor = TilingActor(system: fake, epsilon: eps)
        let t = targets(3)
        for k in 0..<3 { #expect(seed[k].frame != t[k]) }   // genuinely off-grid → writes provable

        await actor.activate(config: enabled())

        let writes = await fake.recordedWrites
        #expect(writes.count == 3)
        #expect(Set(writes.map(\.id)) == Set([1, 2, 3]))
        for w in writes { #expect(w.target == t[Int(w.id) - 1]) }   // EXACT slot targets
    }

    // #14a — activate() re-enumerates the CURRENT windows each call (no stale cache): after the
    // window set changes, a second activate tiles what's on screen NOW.
    @Test("activate re-enumerates the current windows every call")
    func activateReenumerates() async {
        let fake = InMemoryWindowSystem(windows: [off(1), off(2)])
        let actor = TilingActor(system: fake, epsilon: eps)
        await actor.activate(config: enabled())

        await fake.reseed([off(3), off(4), off(5)])   // window set changes out from under it
        await fake.clearWrites()
        await actor.activate(config: enabled())

        let t = targets(3)
        let writes = await fake.recordedWrites
        #expect(Set(writes.map(\.id)) == Set([3, 4, 5]))            // tiled exactly the current set
        for w in writes { #expect(w.target == t[Int(w.id) - 3]) }
    }

    // Disabled config = inert: no writes even over off-grid windows ("Off = no rigid behavior").
    @Test("disabled config: activate issues no writes")
    func disabledInert() async {
        let fake = InMemoryWindowSystem(windows: [off(1), off(2)])
        let actor = TilingActor(system: fake, epsilon: eps)
        await actor.activate(config: TileConfig(isEnabled: false, visibleFrame: visible, gap: gap))
        #expect(await fake.recordedWrites.isEmpty)
    }

    // #26 — ON-DEMAND drag path. windowID(atFresh:) resolves the dragged id by ENUMERATING FRESH at
    // mouse-down — no activate/cached state. Discriminates pick-first (asks for a NON-first window).
    @Test("windowID(atFresh:) resolves from a fresh enumerate")
    func windowIDAtFreshResolves() async {
        let f = targets(4)
        let fake = InMemoryWindowSystem(windows: (0..<4).map { win(CGWindowID($0 + 1), f[$0]) })
        let actor = TilingActor(system: fake, epsilon: eps)
        #expect(await actor.windowID(atFresh: CGPoint(x: f[2].midX, y: f[2].midY)) == 3)   // NOT first
        #expect(await actor.windowID(atFresh: CGPoint(x: -500, y: -500)) == nil)           // a gap
    }

    // #26 — ON-DEMAND reorder: at drag END, reorderDropFresh ENUMERATES FRESH (the dragged window at
    // its dropped position — simulated by the seed), snaps it to the nearest slot, shuffles the rest.
    @Test("reorderDropFresh: fresh-enumerate → nearest-slot snap")
    func reorderDropFreshReorders() async {
        let f = targets(4)
        let dropped = CGRect(x: f[3].midX - 50, y: f[3].midY - 50, width: 100, height: 100)
        let fake = InMemoryWindowSystem(windows: [win(1, dropped), win(2, f[1]), win(3, f[2]), win(4, f[3])])
        let actor = TilingActor(system: fake, epsilon: eps)

        await actor.reorderDropFresh(1, config: enabled())

        let writes = await fake.recordedWrites
        #expect(writes.contains { $0.id == 1 && $0.target == f[3] })   // dragged id1 snaps to slot 3
        let order: [CGWindowID] = [2, 3, 4, 1]
        for w in writes { #expect(w.target == f[order.firstIndex(of: w.id)!]) }
        #expect(Set(writes.map(\.id)) == Set([1, 2, 3, 4]))
    }

    // #26 B1 — AX enumerates z-order, NOT slot order. reorderCommands needs slot order, so
    // reorderDropFresh re-sorts by (minX,minY). Seed a SCRAMBLED order: the NON-dragged windows must
    // still land on their CORRECT slots.
    @Test("reorderDropFresh: correct with a scrambled (non-slot) enumeration order")
    func reorderDropFreshScrambledEnumeration() async {
        let f = targets(4)
        let dropped = CGRect(x: f[3].midX - 50, y: f[3].midY - 50, width: 100, height: 100)
        let scrambled = [win(3, f[2]), win(1, dropped), win(4, f[3]), win(2, f[1])]
        let fake = InMemoryWindowSystem(windows: scrambled)
        let actor = TilingActor(system: fake, epsilon: eps)

        await actor.reorderDropFresh(1, config: enabled())

        let writes = await fake.recordedWrites
        #expect(writes.first { $0.id == 1 }?.target == f[3])   // dragged → slot 3
        #expect(writes.first { $0.id == 2 }?.target == f[0])   // the rest keep slot order,
        #expect(writes.first { $0.id == 3 }?.target == f[1])   // NOT scrambled by z-order
        #expect(writes.first { $0.id == 4 }?.target == f[2])
    }

    @Test("reorderDropFresh for an untracked id is a no-op")
    func reorderDropFreshUntrackedNoop() async {
        let fake = InMemoryWindowSystem(windows: [win(1, targets(2)[0]), win(2, targets(2)[1])])
        let actor = TilingActor(system: fake, epsilon: eps)
        await actor.reorderDropFresh(999, config: enabled())
        #expect(await fake.recordedWrites.isEmpty)
    }
}
