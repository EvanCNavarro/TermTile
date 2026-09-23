@testable import TermTileCore
import Testing

/// EvanCNavarro/TermTile#47 — a turn that ENDED with background shells still running was painted
/// green, i.e. finished. Twice observed live: a Codex session showing "2 background terminals
/// running" and a Claude Code session showing "· 1 shell ·", both tinted `5139,15419,8737`.
///
/// Every fixture below is a real footer captured from a live pane on 2026-09-23, not invented.
@Suite("Pending: background work outstanding after the turn ended")
struct PendingSignalTests {
    /// Claude Code, one background shell running. The count sits in the `⏵⏵` status line, THREE
    /// lines from the end — so the final-line rule that guards the blocked marker (finding 15)
    /// cannot be reused here.
    static let claudeWithShell = """
        ────────────────────────────────────────────────────────────────────
          [Opus 5 (1M context)] │ 📁 Project: weave-verifier │ 🌿 Branch:…
          ⏵⏵ bypass permissions on · 1 shell · ← 1 agent · 1 feedback dra…
                                    ✔ Update installed · Restart to update
                                                                       /rc
        """

    /// The SAME session with the shell finished — the only difference is the count. Captured by
    /// starting exactly one background shell and letting it end.
    static let claudeNoShell = """
        ────────────────────────────────────────────────────────────────────
          [Opus 5 (1M context)] │ 📁 Project: weave-verifier │ 🌿 Branch:…
          ⏵⏵ bypass permissions on (shift+tab to cycle) · ← 1 agent
                                    ✔ Update installed · Restart to update
                                                                       /rc
        """

    /// Claude Code, three shells — plural, and the same line carries other `·`-separated items.
    static let claudeThreeShells = """
          [Opus 5 (1M context)] │ 📁 Project: marketing-score-app │ 🌿 Br…
          ⏵⏵ bypass permissions on · 3 shells · ← 1 agent · 1 feedback dr…
                                    ✔ Update installed · Restart to update
          ⧉  Docs
        """

    /// Codex — a different agent, different wording, different chrome.
    static let codexWithTerminals = """
        ─ Worked for 1h 21m 59s ────────────────────────────────────────────
          2 background terminals running · /ps to view · /stop to close
        › Ask Codex to do anything
          gpt-5.5 xhigh · ~ · Main [default]            Goal achieved (7m)
        """

    /// THE FALSE-POSITIVE GUARD — a session that merely QUOTES a footer, with a clean real footer
    /// below it. This is #34's failure in a new costume: the blocked marker got painted amber
    /// because a session printed the string, and this investigation wrote several shell counts
    /// into its own scrollback.
    ///
    /// DELIBERATELY SHORT LINES. The first version of this fixture ran to ~560 characters, so
    /// `tail.suffix(400)` cut the quoted lines before any guard saw them — the truncation was
    /// doing the work and the footer-window guard was never exercised. Planting a defect in that
    /// guard did not fail the test, which is how the vacuum was found. Kept under 400 characters
    /// so the quoted text genuinely reaches the classifier.
    static let quotesAFooterButIsIdle = """
        ⏵⏵ on · 1 shell · ← 1 agent
        DURING ⏵⏵ on · 2 shells · ok
        absent, present, absent
        ──────────────
        [Opus 5] │ termtile
        ⏵⏵ bypass permissions on
        ✔ Update installed
        /rc
        """

    /// The count phrase on a footer line with NO chrome — it must not match on the phrase alone.
    /// Synthetic: it exists to pin the chrome guard, which realistic input does not exercise.
    static let countWithoutChrome = """
        ──────────────
        [Opus 5] │ termtile
        launched 1 shell earlier
        ✔ Update installed
        /rc
        """

    /// Chrome and the bare word, with NO number. Also synthetic, and also load-bearing: without
    /// the digit test any footer mentioning a shell would paint blue.
    static let chromeWithoutCount = """
        ──────────────
        [Opus 5] │ termtile
        ⏵⏵ bypass permissions · shell
        ✔ Update installed
        /rc
        """

    /// iTerm pads with NUL where cells are empty; the production AX read sees those, an
    /// AppleScript read sees spaces. `normalize` maps NUL to space, so both must classify alike.
    static let claudeWithShellNULPadded = """
        ──────────────────────────────
        \u{0}\u{0}[Opus 5 (1M context)]\u{0}│\u{0}📁 Project:\u{0}weave-verifier
        \u{0}\u{0}⏵⏵\u{0}bypass\u{0}permissions\u{0}on\u{0}·\u{0}1\u{0}shell\u{0}·\u{0}←\u{0}1\u{0}agent
        \u{0}\u{0}\u{0}\u{0}✔\u{0}Update\u{0}installed\u{0}·\u{0}Restart\u{0}to\u{0}update
        \u{0}\u{0}\u{0}\u{0}/rc
        """

    static let interrupt = "• Working (15s · esc to interrupt)"
    static let blockedMarker = "Esc to cancel"

    struct Row {
        let label: String
        let tail: String
        let widerTail: String
        let delta: Int?
        let expected: AgentState
    }

    static var table: [Row] {
        [
            // Rows 1-3: PENDING — the new behaviour. Turn over, nothing rendering, work outstanding.
            Row(label: "1 claude 1 shell, idle", tail: claudeWithShell, widerTail: claudeWithShell,
                delta: 0, expected: .pending),
            Row(label: "2 claude 3 shells, idle", tail: claudeThreeShells,
                widerTail: claudeThreeShells, delta: 0, expected: .pending),
            Row(label: "3 codex terminals, idle", tail: codexWithTerminals,
                widerTail: codexWithTerminals, delta: 0, expected: .pending),
            Row(label: "4 NUL-padded, idle", tail: claudeWithShellNULPadded,
                widerTail: claudeWithShellNULPadded, delta: 0, expected: .pending),

            // Rows 5-6: WORKING still outranks pending. A live session is live.
            Row(label: "5 shell + delta moved", tail: claudeWithShell, widerTail: claudeWithShell,
                delta: 40, expected: .working),
            Row(label: "6 shell + interrupt shown", tail: claudeWithShell,
                widerTail: claudeWithShell + "\n" + interrupt, delta: 0, expected: .working),

            // Row 7: BLOCKED still outranks everything — waiting on a human beats waiting on a shell.
            Row(label: "7 shell + blocked marker", tail: claudeWithShell + "\n" + blockedMarker,
                widerTail: claudeWithShell, delta: 0, expected: .blocked),

            // Row 8: no baseline paints NOTHING, pending included. Never decide on first sight.
            Row(label: "8 shell, no baseline", tail: claudeWithShell, widerTail: claudeWithShell,
                delta: nil, expected: .unknown),

            // Rows 9-10: READY is unchanged where it was already right.
            Row(label: "9 no shell, idle", tail: claudeNoShell, widerTail: claudeNoShell,
                delta: 0, expected: .ready),
            Row(label: "10 quotes a footer, idle", tail: quotesAFooterButIsIdle,
                widerTail: quotesAFooterButIsIdle, delta: 0, expected: .ready),
            Row(label: "11 count without chrome", tail: countWithoutChrome,
                widerTail: countWithoutChrome, delta: 0, expected: .ready),
            Row(label: "12 chrome without count", tail: chromeWithoutCount,
                widerTail: chromeWithoutCount, delta: 0, expected: .ready)
        ]
    }

    @Test("the whole state space, enumerated")
    func transitionTable() {
        let rows = Self.table
        #expect(rows.count == 12, "the table shrank — a state stopped being covered")
        for row in rows {
            let got = AgentStateClassifier.classify(
                StateEvidence(tail: row.tail, widerTail: row.widerTail, charCountDelta: row.delta),
                blocked: [Self.blockedMarker])
            #expect(got == row.expected, "row \(row.label): expected \(row.expected), got \(got)")
        }
    }

    /// The fixtures must actually DIFFER in the one way that matters, or rows 1 and 9 would be
    /// testing the same string and both could pass on a broken classifier.
    @Test("the with-shell and without-shell fixtures differ only in the count")
    func fixturesAreNotIdentical() {
        #expect(Self.claudeWithShell != Self.claudeNoShell)
        #expect(Self.claudeWithShell.contains("1 shell"))
        #expect(!Self.claudeNoShell.contains("shell ·"))
    }

    /// The false-positive fixtures must SURVIVE the tail truncation, or they test nothing —
    /// `classify` only ever sees the last `tailWindow` characters. This is the assertion that
    /// would have caught the vacuum in the first version.
    @Test("the false-positive fixtures reach the classifier intact")
    func falsePositiveFixturesAreNotTruncatedAway() {
        for (name, fixture) in [("quotesAFooter", Self.quotesAFooterButIsIdle),
                                ("countWithoutChrome", Self.countWithoutChrome),
                                ("chromeWithoutCount", Self.chromeWithoutCount)] {
            let limit = AgentStateClassifier.tailWindow
            #expect(fixture.count <= limit,
                    "\(name) is \(fixture.count) chars; suffix(\(limit)) would cut it, so truncation would pass the test instead of the guard")
        }
        // And the quoted counts must actually be present, or row 10 asserts nothing.
        #expect(Self.quotesAFooterButIsIdle.contains("1 shell"))
        #expect(Self.quotesAFooterButIsIdle.contains("⏵⏵"))
    }
}
