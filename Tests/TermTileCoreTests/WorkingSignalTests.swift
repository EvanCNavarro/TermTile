@testable import TermTileCore
import Testing

/// Fixtures are the real numbers measured on 2026-08-31 across 4 samples of 6 live sessions,
/// with ground truth taken from the session-name glyph.
@Suite("Working signal — measured, not guessed")
struct WorkingSignalTests {
    static func evidence(delta: Int?, interrupt: Bool) -> StateEvidence {
        StateEvidence(tail: "",
                      widerTail: interrupt ? "• Working (15s · esc to interrupt)" : "❯ idle prompt",
                      charCountDelta: delta)
    }

    /// termtile, sample 0: the count moved but the interrupt affordance was outside the window.
    @Test("a moved character count alone means working")
    func movedCountAlone() {
        #expect(WorkingSignal.isWorking(Self.evidence(delta: 4, interrupt: false)))
    }

    /// THE ONE THAT WOULD HAVE BEEN MISSED. termtile, sample 1: the count went DOWN by 18 as
    /// scrollback re-rendered. A `delta > 0` test scores this idle and paints a working window
    /// green.
    @Test("a NEGATIVE delta is still movement, not idleness")
    func negativeDeltaIsWorking() {
        #expect(WorkingSignal.isWorking(Self.evidence(delta: -18, interrupt: false)))
    }

    /// evancnavarro, samples 0 and 3: a Codex session held its count steady while running.
    @Test("a still count with an interrupt affordance means working")
    func interruptAloneMeansWorking() {
        #expect(WorkingSignal.isWorking(Self.evidence(delta: 0, interrupt: true)))
    }

    /// The four idle sessions, 16 observations, all of this shape.
    @Test("a still count with no interrupt affordance is not working")
    func idleIsNotWorking() {
        #expect(!WorkingSignal.isWorking(Self.evidence(delta: 0, interrupt: false)))
    }

    /// First poll of a session: no previous sample, so the delta cannot speak.
    @Test("a missing delta does not by itself mean working")
    func missingDeltaAlone() {
        #expect(!WorkingSignal.isWorking(Self.evidence(delta: nil, interrupt: false)))
        #expect(WorkingSignal.isWorking(Self.evidence(delta: nil, interrupt: true)))
    }

    /// The wider tail carries the same NUL padding as the short one.
    @Test("NUL padding in the wider tail does not block the interrupt match")
    func nulPaddedWiderTail() {
        let e = StateEvidence(tail: "", widerTail: "esc\u{0}to\u{0}interrupt", charCountDelta: 0)
        #expect(WorkingSignal.isWorking(e))
    }
}

@Suite("Full classification from poll evidence")
struct StateEvidenceClassificationTests {
    static func evidence(tail: String = "", delta: Int?, interrupt: Bool = false) -> StateEvidence {
        StateEvidence(tail: tail,
                      widerTail: interrupt ? "esc to interrupt" : "quiet",
                      charCountDelta: delta)
    }

    /// Blocked outranks working: a session can be mid-render AND waiting on a human, and the
    /// human is the fact that matters.
    @Test("blocked outranks working even when the count is moving")
    func blockedOutranksWorking() {
        let e = Self.evidence(tail: "⧉  waiting-on-a-person", delta: 99, interrupt: true)
        #expect(AgentStateClassifier.classify(e) == .blocked)
    }

    @Test("movement classifies working")
    func moving() {
        #expect(AgentStateClassifier.classify(Self.evidence(delta: 7)) == .working)
    }

    @Test("stillness with a measured delta classifies ready")
    func stillWithDelta() {
        #expect(AgentStateClassifier.classify(Self.evidence(delta: 0)) == .ready)
    }

    /// THE FALSE-GREEN GUARD. On the first poll there is no delta, so stillness has not been
    /// observed — only assumed. Painting green here is exactly finding 8's failure.
    @Test("stillness WITHOUT a measured delta is unknown, never ready")
    func stillWithoutDeltaIsUnknown() {
        #expect(AgentStateClassifier.classify(Self.evidence(delta: nil)) == .unknown)
    }

    @Test("an interrupt affordance blocks ready even with a still count")
    func interruptBlocksReady() {
        #expect(AgentStateClassifier.classify(Self.evidence(delta: 0, interrupt: true)) == .working)
    }
}
