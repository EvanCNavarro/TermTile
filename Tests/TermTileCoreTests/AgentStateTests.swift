@testable import TermTileCore
import Testing

/// Fixtures are real tails captured from live sessions during the 2026-08-28 probe
/// (ADR-0006 finding 1), not invented strings.
@Suite("Agent state — classified from the scrollback TAIL only")
struct AgentStateTests {
    /// Bluebox, mid-turn, blocked on a human. Captured verbatim.
    static let blockedTail = """
          [Opus 5 (1M context)] │ 📁 Project: invela-marketing-suite │ 🌿 …
          ⏵⏵ bypass permissions on · 2 shells · ← 1 agent
                                    ✔ Update installed · Restart to update
                                                                       /rc
          ⧉  waiting-on-a-person
        """

    /// PR-Check, actively working.
    static let workingTail = """
        • Ran 7 commands · ctrl + t to view transcript
        • Working (15s · esc to interrupt)
        """

    /// termtile, idle at the prompt.
    static let readyTail = """
        ❯
        ────────────────────────────────────────────────────────────────────
          [Opus 5 (1M context)] │ 📁  Project: termtile │ 🌿  Branch: maste…
          ⏵⏵ bypass permissions on (shift+tab to cycle) · ← 1 agent
        """

    @Test("a blocked session reads as blocked")
    func blocked() {
        #expect(AgentStateClassifier.classify(scrollback: Self.blockedTail) == .blocked)
    }

    @Test("a working session reads as working")
    func working() {
        #expect(AgentStateClassifier.classify(scrollback: Self.workingTail) == .working)
    }

    @Test("an idle session reads as ready")
    func ready() {
        #expect(AgentStateClassifier.classify(scrollback: Self.readyTail) == .ready)
    }

    @Test("unrecognised output is unknown, never a guessed default")
    func unrecognised() {
        #expect(AgentStateClassifier.classify(scrollback: "$ ls -la\ntotal 0\n") == .unknown)
    }

    @Test("empty scrollback is unknown")
    func empty() {
        #expect(AgentStateClassifier.classify(scrollback: "") == .unknown)
    }

    /// Blocked outranks working: "finished" and "waiting on you" are otherwise
    /// indistinguishable, which is the whole reason the out-of-tree hook existed.
    @Test("blocked outranks working when both markers are in the tail")
    func blockedBeatsWorking() {
        let both = "• Working (3s · esc to interrupt)\n⧉  waiting-on-a-person\n"
        #expect(AgentStateClassifier.classify(scrollback: both) == .blocked)
    }

    /// THE VACUITY KILLER. The buffer holds up to ~44k chars of history, so a whole-buffer
    /// implementation would let a marker from thousands of lines ago decide the CURRENT
    /// state. This fixture puts a blocked marker deep in history and a clean tail after it:
    /// a correct classifier says unknown, a whole-buffer one says blocked.
    @Test("a marker stranded in scrollback history does NOT decide the current state")
    func staleMarkerInHistoryIsIgnored() {
        let ancient = "⧉  waiting-on-a-person\n"
        let filler = String(repeating: "irrelevant scrollback line\n", count: 400)
        #expect(filler.count > AgentStateClassifier.tailWindow,
                "filler must exceed the tail window or this test proves nothing")
        #expect(AgentStateClassifier.classify(scrollback: ancient + filler) == .unknown)
    }

    /// The mirror of the above — the tail window must still be wide enough to SEE a real
    /// marker. A classifier that looked at only the last few characters would pass the test
    /// above for the wrong reason.
    @Test("a marker inside the tail window is still seen")
    func recentMarkerIsSeen() {
        let old = String(repeating: "old line\n", count: 400)
        #expect(AgentStateClassifier.classify(scrollback: old + Self.blockedTail) == .blocked)
    }
}
