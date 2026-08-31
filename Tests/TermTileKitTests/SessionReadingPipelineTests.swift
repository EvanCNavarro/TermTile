@testable import TermTileKit
import TermTileCore
import Testing

/// Proves the port composes with the Core classifiers into the decision the coordinator will
/// make: pane -> (tty, state). Plain values throughout — no AX, no terminal.
@Suite("Session reading pipeline — port + join + classify")
struct SessionReadingPipelineTests {
    static let sessions = [
        TTYSessionSnapshot(tty: "/dev/ttys003", windowIndex: 3, tabIndex: 0, paneIndex: 0,
                           cwd: "invela-marketing-suite"),
        TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0, paneIndex: 0,
                           cwd: "termtile")
    ]

    /// Tails are real captures from the 2026-08-28 probe.
    /// An idle-looking tail with NO recognised marker. It was a blocked fixture until the marker
    /// it relied on was found to be a task label (EvanCNavarro/TermTile#6); `.unknown` is the
    /// honest classification for a pane carrying no verified marker.
    static let unknownPane = ObservedPane(
        snapshot: AXPaneSnapshot(windowBadge: 4, cwd: "invela-marketing-suite"),
        scrollbackTail: "  /rc\n  ⧉  some-task-label\n", characterCount: 1000)
    /// A WORKING tail, not a ready one. Ready-detection was withdrawn on 2026-08-31 after
    /// `shift+tab to cycle` was measured on a window that was actively running a command
    /// (ADR-0006 finding 8) — so this pane exercises the second real state the pipeline can
    /// currently produce.
    static let workingPane = ObservedPane(
        snapshot: AXPaneSnapshot(windowBadge: 6, cwd: "termtile"),
        scrollbackTail: "• Ran 7 commands\n• Working (15s · esc to interrupt)\n", characterCount: 2000)

    @Test("panes resolve to their ttys and classify to their states")
    func endToEnd() async {
        let reader = InMemorySessionReader(panes: [Self.unknownPane, Self.workingPane])
        let panes = await reader.visiblePanes()
        #expect(panes.count == 2)

        let outcomes = SessionJoin.resolve(panes: panes.map(\.snapshot), sessions: Self.sessions)
        #expect(outcomes.count == 2)
        #expect(outcomes == [.resolved(tty: "/dev/ttys003"), .resolved(tty: "/dev/ttys005")])

        let states = panes.map { AgentStateClassifier.classify(scrollback: $0.scrollbackTail) }
        #expect(states == [.unknown, .working])
    }

    /// The negative contract end-to-end: an unresolvable pane must produce NO tty to write to.
    @Test("an unresolvable pane yields no tty, so nothing gets tinted")
    func ambiguousProducesNoTarget() async {
        let shared = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 9, tabIndex: 0, paneIndex: 0, cwd: "same"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 10, tabIndex: 0, paneIndex: 0, cwd: "same")
        ]
        let pane = ObservedPane(snapshot: AXPaneSnapshot(windowBadge: nil, cwd: "same"),
                                scrollbackTail: "• Working (3s · esc to interrupt)",
                                characterCount: 500)
        let reader = InMemorySessionReader(panes: [pane])
        let panes = await reader.visiblePanes()
        #expect(panes.count == 1)

        let outcomes = SessionJoin.resolve(panes: panes.map(\.snapshot), sessions: shared)
        #expect(outcomes == [.ambiguous(.cwdNotUnique)])

        // The state is knowable; the TARGET is not. Both facts must survive to the caller, or it
        // would tint a guessed window with a correctly-read state — the worst of both.
        #expect(AgentStateClassifier.classify(scrollback: panes[0].scrollbackTail) == .working)
        let targets = outcomes.compactMap { outcome -> String? in
            if case .resolved(let tty) = outcome { return tty }
            return nil
        }
        #expect(targets.isEmpty, "an ambiguous join must yield zero write targets")
    }

    @Test("the port is polled, not read once and cached")
    func pollsEachTime() async {
        let reader = InMemorySessionReader(panes: [Self.workingPane])
        _ = await reader.visiblePanes()
        await reader.reseed([])
        let second = await reader.visiblePanes()
        #expect(second.isEmpty, "a reseeded reader must reflect the new world")
        #expect(await reader.readCount == 2)
    }
}
