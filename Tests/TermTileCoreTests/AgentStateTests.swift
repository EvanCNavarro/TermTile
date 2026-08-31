@testable import TermTileCore
import Testing

/// Fixtures are real tails captured from live sessions during the 2026-08-28 probe
/// (ADR-0006 finding 1), not invented strings.
@Suite("Agent state — classified from the scrollback TAIL only")
struct AgentStateTests {
    /// A SYNTHETIC blocked tail. The real capture that used to live here was
    /// `⧉  waiting-on-a-person`, which turned out to be Claude Code's task LABEL, not a state
    /// (see AgentStateTaskLabelTests). No verified blocked marker exists yet, so these tests use
    /// a placeholder plus the marker-set seam — the SEMANTICS stay covered while the vocabulary
    /// is empty. Tracked as EvanCNavarro/TermTile#6.
    static let blockedMarker = "NEEDS-YOUR-ANSWER"
    static let blockedTail = """
          [Opus 5 (1M context)] │ 📁 Project: invela-marketing-suite │ 🌿 …
          ⏵⏵ bypass permissions on · 2 shells · ← 1 agent
                                    ✔ Update installed · Restart to update
                                                                       /rc
          NEEDS-YOUR-ANSWER
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
        #expect(AgentStateClassifier.classify(scrollback: Self.blockedTail,
                                             blocked: [Self.blockedMarker]) == .blocked)
    }

    @Test("a working session reads as working")
    func working() {
        #expect(AgentStateClassifier.classify(scrollback: Self.workingTail) == .working)
    }

    /// MEASURED 2026-08-31: this tail was captured from a window that was ACTIVELY RUNNING a
    /// command, so `shift+tab to cycle` cannot mean idle. Ready-detection is therefore absent
    /// rather than wrong, and an idle-looking session is untinted (ADR-0006 finding 8, #6).
    @Test("the old ready marker no longer fires — it was present on a WORKING window")
    func formerReadyMarkerDoesNotFalselyGreen() {
        #expect(AgentStateClassifier.classify(scrollback: Self.readyTail) == .unknown)
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
        let both = "• Working (3s · esc to interrupt)\nNEEDS-YOUR-ANSWER\n"
        #expect(AgentStateClassifier.classify(scrollback: both,
                                             blocked: [Self.blockedMarker]) == .blocked)
    }

    /// THE VACUITY KILLER. The buffer holds up to ~44k chars of history, so a whole-buffer
    /// implementation would let a marker from thousands of lines ago decide the CURRENT
    /// state. This fixture puts a blocked marker deep in history and a clean tail after it:
    /// a correct classifier says unknown, a whole-buffer one says blocked.
    @Test("a marker stranded in scrollback history does NOT decide the current state")
    func staleMarkerInHistoryIsIgnored() {
        let ancient = "NEEDS-YOUR-ANSWER\n"
        let filler = String(repeating: "irrelevant scrollback line\n", count: 400)
        #expect(filler.count > AgentStateClassifier.tailWindow,
                "filler must exceed the tail window or this test proves nothing")
        #expect(AgentStateClassifier.classify(scrollback: ancient + filler,
                                             blocked: [Self.blockedMarker]) == .unknown)
    }

    /// The mirror of the above — the tail window must still be wide enough to SEE a real
    /// marker. A classifier that looked at only the last few characters would pass the test
    /// above for the wrong reason.
    @Test("a marker inside the tail window is still seen")
    func recentMarkerIsSeen() {
        let old = String(repeating: "old line\n", count: 400)
        #expect(AgentStateClassifier.classify(scrollback: old + Self.blockedTail,
                                             blocked: [Self.blockedMarker]) == .blocked)
    }
}

/// iTerm2's AX text carries U+0000 NUL where padding cells sit, so the rendered
/// "shift+tab to cycle" arrives as "shift+tab\0to\0cycle". Measured 2026-08-31 on a live
/// session; it is why space-containing markers flapped between matching and not, while the
/// hyphenated `waiting-on-a-person` always matched.
@Suite("Agent state — NUL padding in iTerm's AX text")
struct AgentStateNormalizationTests {
    /// The exact scalars read off a live pane.
    /// Normalization is proven by the WORKING marker instead, since the ready marker was
    /// withdrawn for being a false green. The NUL handling is the same code path.
    @Test("a NUL-padded former-ready marker does not resurrect a false green")
    func nulPaddedFormerReadyStaysUnknown() {
        let real = "ions\u{0}on (shift+tab\u{0}to\u{0}cycle) · ← 1 agent"
        #expect(AgentStateClassifier.classify(scrollback: real) == .unknown)
    }

    @Test("NUL-padded working marker still classifies working")
    func nulPaddedWorking() {
        #expect(AgentStateClassifier.classify(scrollback: "Working (15s · esc\u{0}to\u{0}interrupt)")
            == .working)
    }

    @Test("other C0 control characters are normalized too")
    func otherControls() {
        #expect(AgentStateClassifier.classify(scrollback: "esc\u{1}to\u{2}interrupt") == .working)
    }

    /// The widening guard. Normalizing must not join LINES, or a marker's words appearing on
    /// two different rows would fabricate a match that was never on screen.
    @Test("normalization does not join lines into a marker that was never rendered")
    func doesNotJoinLines() {
        #expect(AgentStateClassifier.classify(scrollback: "esc\nto interrupt") == .unknown)
        #expect(AgentStateClassifier.classify(scrollback: "NEEDS-YOUR\nANSWER",
                                             blocked: ["NEEDS-YOUR-ANSWER"]) == .unknown)
    }

    /// Runs of padding collapse to a single space, which is what the marker text assumes.
    @Test("repeated padding collapses rather than blocking the match")
    func collapsesRuns() {
        #expect(AgentStateClassifier.classify(scrollback: "esc\u{0}\u{0}\u{0} to  interrupt")
            == .working)
    }
}

/// MEASURED 2026-08-31, and it corrects a defect that shipped.
///
/// `⧉ <text>` is Claude Code's per-session TASK LABEL slot, not a state indicator. Three live
/// sessions carried three different values in it — `waiting-on-a-person`, `icon-marks`,
/// `portfolio-roster` — and ALL THREE were idle (`✳`) by the session-name glyph, while two other
/// sessions had no `⧉` slot at all. If the first meant "blocked on a human", the other two would
/// have to mean the same thing in different words.
///
/// `waiting-on-a-person` was shipped as the sole blocked marker. It reported one session as
/// blocked in every pass for hours while that session was idle.
@Suite("Agent state — the ⧉ slot is a task label, not a state")
struct AgentStateTaskLabelTests {
    /// The exact tail that was misclassified, verbatim from the live session.
    static let labelTail = """
          ✔ Update installed · Restart to update
                                                                     /rc
          NEEDS-YOUR-ANSWER
        """

    @Test("a task label reading like a state does not classify as blocked")
    func taskLabelIsNotBlocked() {
        #expect(AgentStateClassifier.classify(scrollback: Self.labelTail) != .blocked)
    }

    /// The sibling labels prove the slot is generic. If any of these classified, the classifier
    /// would be reading whatever the user happened to name their task.
    @Test("sibling task labels in the same slot classify no differently")
    func siblingLabelsAgree() {
        let icon = Self.labelTail.replacingOccurrences(of: "waiting-on-a-person", with: "icon-marks")
        let roster = Self.labelTail.replacingOccurrences(of: "waiting-on-a-person",
                                                        with: "portfolio-roster")
        let subject = AgentStateClassifier.classify(scrollback: Self.labelTail)
        #expect(AgentStateClassifier.classify(scrollback: icon) == subject)
        #expect(AgentStateClassifier.classify(scrollback: roster) == subject,
                "the classifier's answer depends on what the user named their task")
    }

    /// The full evidence shape: a label-bearing tail and a label-free tail must agree, because the
    /// label carries no state information at all.
    @Test("presence or absence of the label slot does not change the answer")
    func labelPresenceIsIrrelevant() {
        let withoutSlot = """
              ✔ Update installed · Restart to update
                                                                         /rc
            """
        #expect(AgentStateClassifier.classify(scrollback: Self.labelTail)
                == AgentStateClassifier.classify(scrollback: withoutSlot))
    }
}
