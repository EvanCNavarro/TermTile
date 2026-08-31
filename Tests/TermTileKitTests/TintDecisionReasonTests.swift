@testable import TermTileKit
import TermTileCore
import Testing

/// The diagnostics exist so an untinted window explains itself instead of looking broken.
/// A reason that is merely present is not enough — it has to distinguish the cases the user
/// would act on differently.
@Suite("Tint decision — why a session was left alone")
struct TintDecisionReasonTests {
    static func decision(state: AgentState, wrote: Bool, tty: String? = "/dev/ttys005",
                         ambiguity: AmbiguityReason? = nil, hadBaseline: Bool = true) -> TintDecision {
        TintDecision(cwd: "termtile", tty: tty, state: state, wrote: wrote,
                     ambiguity: ambiguity, hadBaseline: hadBaseline)
    }

    @Test("a painted session has nothing to explain")
    func paintedHasNoReason() {
        #expect(Self.decision(state: .ready, wrote: true).untintedReason == nil)
        #expect(Self.decision(state: .blocked, wrote: true).untintedReason == nil)
        #expect(Self.decision(state: .working, wrote: true).untintedReason == nil)
    }

    /// THE DISTINCTION THAT MAKES THIS WORTH BUILDING. Both are `.unknown`, and the user's
    /// correct reaction differs: wait a moment, versus a marker is missing.
    @Test("first sighting reads differently from an unrecognised state")
    func firstSightingIsNotUnrecognised() {
        let firstLook = Self.decision(state: .unknown, wrote: false, hadBaseline: false)
        let unrecognised = Self.decision(state: .unknown, wrote: false, hadBaseline: true)
        #expect(firstLook.untintedReason != nil)
        #expect(unrecognised.untintedReason != nil)
        #expect(firstLook.untintedReason != unrecognised.untintedReason,
                "both .unknown cases produced the same text, so the diagnostic distinguishes nothing")
    }

    /// Each join failure has its own cause and its own remedy, so each needs its own words.
    @Test("every ambiguity reason produces a distinct explanation")
    func ambiguityReasonsAreDistinct() {
        let all = [AmbiguityReason.cwdNotUnique, .noCandidate, .multipleCandidates]
        let texts = all.map { Self.decision(state: .unknown, wrote: false, tty: nil,
                                            ambiguity: $0).untintedReason }
        #expect(texts.allSatisfy { $0 != nil })
        #expect(Set(texts.compactMap { $0 }).count == all.count,
                "two ambiguity reasons share wording: \(texts)")
    }

    /// An unresolved join is the reason, even if the state happens to be knowable — the target,
    /// not the state, is what was missing.
    @Test("an ambiguous join explains the join, not the state")
    func ambiguityOutranksState() {
        let d = Self.decision(state: .blocked, wrote: false, tty: nil, ambiguity: .cwdNotUnique)
        let unrecognised = Self.decision(state: .unknown, wrote: false, hadBaseline: true)
        #expect(d.untintedReason != unrecognised.untintedReason)
    }

    @Test("no explanation is empty or whitespace")
    func reasonsAreSubstantive() {
        let cases = [
            Self.decision(state: .unknown, wrote: false, hadBaseline: false),
            Self.decision(state: .unknown, wrote: false, hadBaseline: true),
            Self.decision(state: .unknown, wrote: false, tty: nil, ambiguity: .cwdNotUnique),
            Self.decision(state: .unknown, wrote: false, tty: nil, ambiguity: .noCandidate),
            Self.decision(state: .unknown, wrote: false, tty: nil, ambiguity: .multipleCandidates)
        ]
        #expect(cases.count == 5)
        for c in cases {
            let reason = c.untintedReason ?? ""
            #expect(!reason.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
