@testable import TermTileKit
import TermTileCore
import Testing

@Suite("Tinting coordinator — the stateful pass")
struct TintingCoordinatorTests {
    static let session = TTYSessionSnapshot(
        tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0, paneIndex: 0, cwd: "termtile")

    static func pane(cwd: String = "termtile", badge: Int? = 6,
                     tail: String = "❯ quiet prompt", count: Int) -> ObservedPane {
        ObservedPane(snapshot: AXPaneSnapshot(windowBadge: badge, cwd: cwd),
                     scrollbackTail: tail, characterCount: count)
    }

    static func rig(panes: [ObservedPane], sessions: [TTYSessionSnapshot] = [session])
        -> (TintingCoordinator, InMemorySessionReader, InMemoryTTYProbe, RecordingTinter) {
        let reader = InMemorySessionReader(panes: panes)
        let probe = InMemoryTTYProbe(sessions: sessions)
        let tinter = RecordingTinter()
        return (TintingCoordinator(reader: reader, probe: probe, writer: tinter), reader, probe, tinter)
    }

    /// THE FALSE-GREEN GUARD, at the level that matters. On the very first pass there is no
    /// previous count, so stillness has not been observed and nothing may be painted.
    @Test("the first pass has no delta, so it classifies unknown and writes nothing")
    func firstPassWritesNothing() async {
        let (coord, _, _, tinter) = Self.rig(panes: [Self.pane(count: 1000)])
        let decisions = await coord.pass()
        #expect(decisions.count == 1)
        #expect(decisions.first?.state == .unknown)
        #expect(decisions.first?.wrote == false)
        #expect(await tinter.writes.isEmpty)
    }

    @Test("a second pass with an unchanged count classifies ready and paints it")
    func steadyCountBecomesReady() async {
        let (coord, reader, _, tinter) = Self.rig(panes: [Self.pane(count: 1000)])
        await coord.pass()
        await reader.reseed([Self.pane(count: 1000)])
        let decisions = await coord.pass()
        #expect(decisions.first?.state == .ready)
        #expect(decisions.first?.wrote == true)
        #expect(await tinter.writtenHexes == [TintPalette.ready.hex])
    }

    @Test("a moved count classifies working and paints normal")
    func movedCountBecomesWorking() async {
        let (coord, reader, _, tinter) = Self.rig(panes: [Self.pane(count: 1000)])
        await coord.pass()
        await reader.reseed([Self.pane(count: 1042)])
        let decisions = await coord.pass()
        #expect(decisions.first?.state == .working)
        #expect(await tinter.writtenHexes == [TintPalette.normal.hex])
    }

    /// A marker-derived state paints on the FIRST pass, with no baseline. Uses the interrupt
    /// affordance because it is the only VERIFIED marker: the blocked marker this test previously
    /// used turned out to be Claude Code's task label (EvanCNavarro/TermTile#6).
    @Test("a marker-derived state paints without needing a delta")
    func markerStateNeedsNoDelta() async {
        let (coord, _, _, tinter) = Self.rig(
            panes: [Self.pane(tail: "• Working (3s · esc to interrupt)", count: 1000)])
        let decisions = await coord.pass()
        #expect(decisions.first?.state == .working)
        #expect(await tinter.writtenHexes == [TintPalette.normal.hex])
    }

    /// An unresolvable pane must produce NO write — the state may be knowable while the target
    /// is not, and painting a guess is the failure the join exists to prevent.
    @Test("an ambiguous join writes nothing and records why")
    func ambiguousWritesNothing() async {
        let shared = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 9, tabIndex: 0, paneIndex: 0, cwd: "same"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 10, tabIndex: 0, paneIndex: 0, cwd: "same")
        ]
        let (coord, _, _, tinter) = Self.rig(
            panes: [Self.pane(cwd: "same", badge: nil,
                              tail: "• Working (3s · esc to interrupt)", count: 500)],
            sessions: shared)
        let decisions = await coord.pass()
        #expect(decisions.first?.tty == nil)
        #expect(decisions.first?.wrote == false)
        #expect(decisions.first?.ambiguity == .cwdNotUnique)
        #expect(await tinter.writes.isEmpty, "an ambiguous pane was painted")
    }

    /// THE RECYCLED-TTY GUARD. A session dies and a NEW one is born on the same tty between two
    /// polls. Presence-based eviction cannot see that — both passes show /dev/ttys005. Keying the
    /// baseline by cwd as well is what stops the new session being measured against the dead
    /// one's count and painted green while it works.
    @Test("a tty reused by a different session does not inherit the dead one's baseline")
    func recycledTTYDoesNotInheritBaseline() async {
        let (coord, reader, probe, tinter) = Self.rig(panes: [Self.pane(count: 1000)])
        await coord.pass()
        await tinter.clear()

        // Same tty, DIFFERENT session — and the same character count, which is exactly the
        // coincidence that would read as stillness.
        await reader.reseed([Self.pane(cwd: "other-project", count: 1000)])
        await probe.reseed([TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5,
                                               tabIndex: 0, paneIndex: 0, cwd: "other-project")])
        let decisions = await coord.pass()
        #expect(decisions.first?.state == .unknown,
                "the new session inherited the dead session's baseline and was classified")
        #expect(await tinter.writes.isEmpty, "a recycled tty was painted on its first sighting")
    }

    @Test("resetAll repaints every touched session to normal")
    func resetAllRepaints() async {
        let (coord, reader, _, tinter) = Self.rig(panes: [Self.pane(count: 1000)])
        await coord.pass()
        await reader.reseed([Self.pane(count: 1000)])
        await coord.pass()
        await tinter.clear()
        await coord.resetAll()
        #expect(await tinter.writtenTTYs == ["/dev/ttys005"])
        #expect(await tinter.writtenHexes == [TintPalette.normal.hex])
    }

    /// Eviction, tested directly. A window that closes must leave no baseline behind — a stale
    /// entry would both survive into a later pass and make resetAll write to a tty that is gone.
    @Test("a session that disappears is evicted from the baseline map")
    func disappearedSessionIsEvicted() async {
        let (coord, reader, probe, tinter) = Self.rig(panes: [Self.pane(count: 1000)])
        await coord.pass()
        await reader.reseed([])
        await probe.reseed([])
        let decisions = await coord.pass()
        #expect(decisions.isEmpty)
        await tinter.clear()
        await coord.resetAll()
        #expect(await tinter.writes.isEmpty,
                "resetAll wrote to a tty whose session had already disappeared")
    }

    @Test("a chosen ready intensity is what gets painted")
    func honoursReadyIntensity() async {
        let reader = InMemorySessionReader(panes: [Self.pane(count: 1000)])
        let tinter = RecordingTinter()
        let coord = TintingCoordinator(reader: reader, probe: InMemoryTTYProbe(sessions: [Self.session]),
                                       writer: tinter, readyColor: TintPalette.readyLoudest)
        await coord.pass()
        await reader.reseed([Self.pane(count: 1000)])
        await coord.pass()
        #expect(await tinter.writtenHexes == [TintPalette.readyLoudest.hex])
    }
}

@Suite("Tinting coordinator — diagnostics fields")
struct TintingCoordinatorDiagnosticsTests {
    /// The first pass has no previous count; the second does. If `hadBaseline` did not track that,
    /// the diagnostics could not separate "just noticed" from "state not recognised".
    @Test("hadBaseline is false on first sighting and true once a baseline exists")
    func baselineTracksAcrossPasses() async {
        let (coord, reader, _, _) = TintingCoordinatorTests.rig(
            panes: [TintingCoordinatorTests.pane(count: 1000)])
        let first = await coord.pass()
        #expect(first.count == 1)
        #expect(first.first?.hadBaseline == false, "a first sighting claimed a baseline")

        await reader.reseed([TintingCoordinatorTests.pane(count: 1000)])
        let second = await coord.pass()
        #expect(second.first?.hadBaseline == true, "a second pass reported no baseline")
    }

    /// An unresolved pane never had a baseline looked up, and must not claim one.
    @Test("an ambiguous pane does not claim a baseline")
    func ambiguousHasNoBaseline() async {
        let shared = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 9, tabIndex: 0, paneIndex: 0, cwd: "same"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 10, tabIndex: 0, paneIndex: 0, cwd: "same")
        ]
        let (coord, _, _, _) = TintingCoordinatorTests.rig(
            panes: [TintingCoordinatorTests.pane(cwd: "same", badge: nil, count: 500)],
            sessions: shared)
        let out = await coord.pass()
        #expect(out.first?.hadBaseline == false)
        #expect(out.first?.untintedReason != nil, "an unpainted pane gave no reason")
    }
}
