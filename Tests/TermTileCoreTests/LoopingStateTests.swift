@testable import TermTileCore
import Testing

/// EvanCNavarro/TermTile#51 — a session running a long `/loop` should hold ONE colour for the
/// whole loop, including the dormant stretches between cycles.
///
/// The dormant stretch is the case that forces this to exist. Measured on a live `/loop /goal`
/// session: during one the pane is idle by every observable signal, so it would paint GREEN —
/// finished — while it is mid-task and about to resume on its own.
@Suite("Looping: one colour for the whole loop, dormant stretches included")
struct LoopingStateTests {
    /// A real footer captured 2026-09-23 from the looping session, mid-dormancy. Nothing here
    /// distinguishes it from a session that has genuinely finished — which is the point.
    static let dormantFooter = """
        ✻ Churned for 54s
        ────────────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────────────
          [Opus 5 (1M context)] │ 📁 Project: server │ 🌿 Branch: fix/fin…
          ⏵⏵ bypass permissions on (shift+tab to cycle) · ← 1 agent
                                                                       /rc
        """

    /// The same session mid-cycle, with a background shell out.
    static let activeFooter = """
        ✻ Brewed for 4m 27s · 1 shell still running
        ────────────────────────────────────────────────────────────────────
          ⏵⏵ bypass permissions on · 1 shell · ← 1 agent · 1 feedback dra…
                                                                       /rc
        """

    static let interrupt = "• Working (15s · esc to interrupt)"
    static let blockedMarker = "Esc to cancel"

    struct Row {
        let label: String
        let looping: Bool
        let tail: String
        let widerTail: String
        let delta: Int?
        let expected: AgentState
    }

    static var table: [Row] {
        [
            // THE ROW THIS FEATURE EXISTS FOR. Dormant between cycles: idle by every signal,
            // and without the flag it paints green/finished.
            Row(label: "1 looping, dormant gap", looping: true, tail: dormantFooter,
                widerTail: dormantFooter, delta: 0, expected: .looping),

            // Held through every other phase of the loop — that is what "one colour" means.
            Row(label: "2 looping, mid-cycle", looping: true, tail: dormantFooter,
                widerTail: dormantFooter, delta: 40, expected: .looping),
            Row(label: "3 looping, interruptible", looping: true, tail: dormantFooter,
                widerTail: dormantFooter + "\n" + interrupt, delta: 0, expected: .looping),
            Row(label: "4 looping, shell out", looping: true, tail: activeFooter,
                widerTail: activeFooter, delta: 0, expected: .looping),

            // No baseline still paints purple: the flag is DECLARED, not inferred from stillness,
            // so it does not need a previous sample the way `ready` does.
            Row(label: "5 looping, no baseline", looping: true, tail: dormantFooter,
                widerTail: dormantFooter, delta: nil, expected: .looping),

            // BLOCKED OUTRANKS THE LOOP. A loop waiting on a human needs the user NOW; purple says
            // "leave it alone", which would be exactly wrong.
            Row(label: "6 looping but blocked", looping: true,
                tail: dormantFooter + "\n" + blockedMarker, widerTail: dormantFooter,
                delta: 0, expected: .blocked),

            // Without the flag, every prior behaviour is untouched.
            Row(label: "7 not looping, dormant", looping: false, tail: dormantFooter,
                widerTail: dormantFooter, delta: 0, expected: .ready),
            Row(label: "8 not looping, shell out", looping: false, tail: activeFooter,
                widerTail: activeFooter, delta: 0, expected: .pending),
            Row(label: "9 not looping, working", looping: false, tail: dormantFooter,
                widerTail: dormantFooter, delta: 40, expected: .working),
            Row(label: "10 not looping, no baseline", looping: false, tail: dormantFooter,
                widerTail: dormantFooter, delta: nil, expected: .unknown)
        ]
    }

    @Test("the whole state space, enumerated")
    func transitionTable() {
        let rows = Self.table
        #expect(rows.count == 10, "the table shrank — a state stopped being covered")
        for row in rows {
            let got = AgentStateClassifier.classify(
                StateEvidence(tail: row.tail, widerTail: row.widerTail,
                              charCountDelta: row.delta, isLooping: row.looping),
                blocked: [Self.blockedMarker])
            #expect(got == row.expected, "row \(row.label): expected \(row.expected), got \(got)")
        }
    }

    /// The dormant fixture must be INDISTINGUISHABLE from a finished session, or rows 1 and 7
    /// would be passing for the wrong reason — the flag would not be what is doing the work.
    @Test("the dormant fixture carries no signal of its own")
    func dormantFixtureIsGenuinelyAmbiguous() {
        let evidence = StateEvidence(tail: Self.dormantFooter, widerTail: Self.dormantFooter,
                                     charCountDelta: 0, isLooping: false)
        #expect(AgentStateClassifier.classify(evidence, blocked: [Self.blockedMarker]) == .ready,
                "the dormant footer resolves to something other than ready on its own, so the flag is not the only thing separating rows 1 and 7")
    }
}
