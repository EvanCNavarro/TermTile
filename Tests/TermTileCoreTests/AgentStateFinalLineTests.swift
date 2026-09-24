@testable import TermTileCore
import Testing

/// EvanCNavarro/TermTile#34 — a session that merely DISPLAYS `Esc to cancel` was painted amber.
///
/// Every fixture here is a real tail read off a live pane through the production AX path on
/// 2026-09-01, not an invented string. The NUL padding is reproduced verbatim (`\u{0}`) because
/// iTerm renders the footer as `Esc<NUL>to<NUL>cancel` — `normalize` mapping NUL to space is what
/// makes the marker match at all, so a fixture with plain spaces would test a string that never
/// appears on screen.
@Suite("Blocked marker must be on the final line")
struct AgentStateFinalLineTests {
    static let marker = "Esc to cancel"

    /// BLOCKED shape 1 — AskUserQuestion. The prompt REPLACES the status footer, so the marker
    /// is the last text in the pane.
    static let blockedAskUserQuestion = """
          ☐ Color

        Red or blue?

        ❯ 1.\u{0}Red
             Pick red.
          2. Blue
             Pick blue.
          3. Type something.
        ────────────────────────────────────────────────────────────────────
          4.\u{0}Chat\u{0}about\u{0}this

        Enter\u{0}to\u{0}select\u{0}\u{0}\u{0}↑/↓\u{0}to\u{0}navigate\u{0}\u{0}\u{0}Esc\u{0}to\u{0}cancel
        """

    /// BLOCKED shape 2 — a clarifying question raised under plan mode. Same family, different
    /// footer wording, and a TRAILING NEWLINE after the marker.
    static let blockedPlanMode = """
          3.\u{0}A\u{0}different\u{0}CLI
        ────────────────────────────────────────────────────────────────────
          Chat\u{0}about\u{0}this

        Enter\u{0}to\u{0}select\u{0}\u{0}\u{0}↑/↓\u{0}to\u{0}navigate\u{0}\u{0}\u{0}n\u{0}to\u{0}add\u{0}notes\u{0}\u{0}\u{0}Esc\u{0}to\u{0}cancel

        """

    /// BLOCKED shape 3 — a Bash PERMISSION-APPROVAL prompt, captured 2026-09-01 by giving a
    /// scratch project a local `permissions.ask` rule (the global config is `defaultMode: auto`
    /// with an empty allowlist, which is why earlier attempts never prompted).
    ///
    /// THIS IS THE OUT-OF-SAMPLE CASE. The rule was designed against two SELECTION prompts; this
    /// is a different UI family and it was never consulted while choosing the rule. It confirms
    /// two decisions that were otherwise only arguments:
    ///
    ///   - Rejecting a co-occurrence rule keyed on `Enter to select` was CORRECT. This footer has
    ///     no such text — it reads `Tab to amend` and `ctrl+e to explain` — so that variant would
    ///     have returned a false NEGATIVE on every permission prompt.
    ///   - "Final LINE", not "end of tail". Here the marker is at the START of its line.
    static let blockedPermissionPrompt = """
        ⏺ Bash(echo hello)
          ⎿  Waiting…
        ────────────────────────────────────────────────────────────────────
        \u{0}Bash command

          \u{0}echo\u{0}hello
           Print hello

        \u{0}Permission rule Bash requires\u{0}confirmation\u{0}for\u{0}this\u{0}command.
        \u{0}/permissions to update rules

        \u{0}Do\u{0}you\u{0}want\u{0}to\u{0}proceed?
        \u{0}❯\u{0}1.\u{0}Yes
        \u{0}\u{0}\u{0}2.\u{0}No

        \u{0}Esc\u{0}to\u{0}cancel\u{0}\u{0}\u{0}Tab\u{0}to\u{0}amend\u{0}\u{0}\u{0}ctrl+e\u{0}to\u{0}explain
        """

    /// THE FALSE POSITIVE — an idle agent session that was asked to print the string. The status
    /// footer is still present BELOW the marker, which is exactly what a real block lacks.
    static let displayedNotBlocked = """
        ⏺ Esc to cancel
        ────────────────────────────────────────────────────────────────────
          [Opus 5 (1M context)] │ 📁 Project: tt-amber-probe-iJeK │ 🔋 Battery: 87% │…
          ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent
                                                                           /rc
        """

    // MARK: - The captures

    @Test("every real blocked capture still classifies blocked")
    func realBlockedCapturesStillBlock() {
        let captures = [("AskUserQuestion", Self.blockedAskUserQuestion),
                        ("plan mode", Self.blockedPlanMode),
                        ("Bash permission prompt", Self.blockedPermissionPrompt)]
        #expect(captures.count == 3)
        for (name, tail) in captures {
            #expect(AgentStateClassifier.classify(scrollback: tail, blocked: [Self.marker]) == .blocked,
                    "\(name) capture stopped classifying blocked")
        }
    }

    @Test("the displayed-marker capture no longer classifies blocked")
    func displayedMarkerDoesNotBlock() {
        #expect(AgentStateClassifier.classify(scrollback: Self.displayedNotBlocked,
                                              blocked: [Self.marker]) != .blocked)
    }

    /// Why the co-occurrence rule was rejected, as an assertion rather than a comment. If someone
    /// later "improves" the rule by also requiring `Enter to select`, this fails and says why.
    @Test("the permission prompt carries no Enter-to-select, so co-occurrence would miss it")
    func permissionPromptLacksSelectionAffordance() {
        let normalized = AgentStateClassifier.normalize(Self.blockedPermissionPrompt)
        #expect(normalized.contains("Esc to cancel"), "the marker itself must be present")
        #expect(!normalized.contains("Enter to select"),
                "if this ever becomes true the co-occurrence rule is worth revisiting")
        #expect(normalized.contains("Tab to amend"), "fixture drifted from the capture")
    }

    // MARK: - The full transition table
    //
    // Enumerated BEFORE the change so exactly the intended rows move. Rows 5-8 are the fix;
    // every other row must read the same before and after.

    struct Row {
        let label: String
        let tail: String
        let widerTail: String
        let delta: Int?
        let expected: AgentState
    }

    static let interrupt = "• Working (15s · esc to interrupt)"

    static var table: [Row] {
        let onFinal = blockedAskUserQuestion
        let offFinal = displayedNotBlocked
        let noMarker = """
              ❯
            ────────────────────────────────────────────────────────────────
              [Opus 5 (1M context)] │ 📁  Project: termtile
            """
        return [
            Row(label: "1 marker final-line, no delta", tail: onFinal, widerTail: onFinal,
                delta: nil, expected: .blocked),
            Row(label: "2 marker final-line, delta 0", tail: onFinal, widerTail: onFinal,
                delta: 0, expected: .blocked),
            Row(label: "3 marker final-line, delta 5", tail: onFinal, widerTail: onFinal,
                delta: 5, expected: .blocked),
            Row(label: "4 marker final-line, interrupt present", tail: onFinal,
                widerTail: onFinal + "\n" + interrupt, delta: 0, expected: .blocked),
            Row(label: "5 marker off-final, no delta", tail: offFinal, widerTail: offFinal,
                delta: nil, expected: .unknown),
            Row(label: "6 marker off-final, delta 0", tail: offFinal, widerTail: offFinal,
                delta: 0, expected: .ready),
            Row(label: "7 marker off-final, delta 5", tail: offFinal, widerTail: offFinal,
                delta: 5, expected: .working),
            Row(label: "8 marker off-final, interrupt present", tail: offFinal,
                widerTail: offFinal + "\n" + interrupt, delta: 0, expected: .working),
            Row(label: "9 no marker, no delta", tail: noMarker, widerTail: noMarker,
                delta: nil, expected: .unknown),
            Row(label: "10 no marker, delta 0", tail: noMarker, widerTail: noMarker,
                delta: 0, expected: .ready),
            Row(label: "11 no marker, delta 5", tail: noMarker, widerTail: noMarker,
                delta: 5, expected: .working),
            Row(label: "12 no marker, interrupt present", tail: noMarker,
                widerTail: noMarker + "\n" + interrupt, delta: 0, expected: .working)
        ]
    }

    @Test("the whole state space, enumerated")
    func transitionTable() {
        let rows = Self.table
        #expect(rows.count == 12, "the table shrank — a state stopped being covered")
        for row in rows {
            let got = AgentStateClassifier.classify(
                StateEvidence(tail: row.tail, widerTail: row.widerTail, charCountDelta: row.delta),
                blocked: [Self.marker])
            #expect(got == row.expected, "row \(row.label): expected \(row.expected), got \(got)")
        }
    }
}

/// EvanCNavarro/TermTile#39 — the standing watch found a real false negative on 2026-09-23.
///
/// A WebFetch permission prompt is genuinely blocked on the user, yet its footer carries NO
/// `Esc to cancel` at all: the escape affordance is rendered inline as `(esc)` inside option 3.
/// Captured live, and the window was painted GREEN — finished — while waiting for an answer.
///
/// Found by DRIVING the state rather than waiting to observe it. Six shapes have now been driven
/// deliberately; this is the first that the marker set missed.
@Suite("Blocked: the permission family that carries no Esc-to-cancel")
struct BlockedWebFetchFamilyTests {
    /// Real capture, 2026-09-23. Note the final line: the only escape hint is `(esc)`.
    static let webFetchPrompt = """
          Claude wants to fetch content from example.com
        Permission rule WebFetch requires confirmation for this tool.
        /permissions to update rules
        Do you want to allow Claude to fetch this content?
        ❯ 1. Yes
          2. Yes, and don't ask again for example.com
          3. No, and tell Claude what to do differently (esc)
        """

    /// The two markers together must cover it; neither alone does.
    static let markers = ["Esc to cancel", "tell Claude what to do differently"]

    @Test("the capture genuinely lacks the original marker")
    func captureLacksOriginalMarker() {
        #expect(!Self.webFetchPrompt.contains("Esc to cancel"),
                "fixture drifted — if it now contains the marker it is not this defect")
        #expect(Self.webFetchPrompt.contains("tell Claude what to do differently"))
    }

    @Test("the original marker set MISSES it — this is the defect")
    func originalMarkerSetMisses() {
        #expect(AgentStateClassifier.classify(scrollback: Self.webFetchPrompt,
                                              blocked: ["Esc to cancel"]) != .blocked)
    }

    @Test("the widened marker set catches it")
    func widenedMarkerSetCatches() {
        #expect(AgentStateClassifier.classify(scrollback: Self.webFetchPrompt,
                                              blocked: Self.markers) == .blocked)
    }

    /// THE ONE THAT MATTERS. The three tests above inject a marker set through the test seam, so
    /// they pass whether or not PRODUCTION carries the new marker — a green that proves the
    /// mechanism and not the shipped behaviour. This calls the production overload.
    @Test("the SHIPPED classifier catches it")
    func productionCatchesIt() {
        #expect(AgentStateClassifier.classify(scrollback: Self.webFetchPrompt) == .blocked,
                "production blockedMarkers does not cover the WebFetch permission family")
    }

    /// The new marker must still obey the final-line rule, or it reopens #34 on a new string.
    @Test("a session merely quoting the new marker is not blocked")
    func quotingTheNewMarkerIsNotBlocked() {
        let quoting = """
            it said "No, and tell Claude what to do differently"
            ──────────────
            [Opus 5] │ termtile
            ⏵⏵ bypass permissions on
            /rc
            """
        #expect(AgentStateClassifier.classify(scrollback: quoting, blocked: Self.markers) != .blocked)
    }
}
