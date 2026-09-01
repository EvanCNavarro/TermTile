import Foundation

/// What a terminal session's agent is doing, derived from the session's visible scrollback
/// (ADR-0006 finding 1: the state signal is literal on-screen text, so no hook is needed).
///
/// `unknown` is first-class and load-bearing: a session whose state cannot be recognised MUST
/// NOT be tinted. Guessing would report one state while the session is in another, which is
/// the silent-lie failure ADR-0006 rejects for the join and rejects here for the same reason.
public enum AgentState: String, Equatable, Sendable {
    /// Idle at a prompt — finished, nothing pending.
    case ready
    /// Actively working.
    case working
    /// Blocked on a human answering something.
    case blocked
    /// No recognised marker. Caller leaves the session at its normal colour.
    case unknown
}

/// Classifies a session's `AgentState` from its scrollback.
///
/// PURE (ADR-0001 rule 1). The markers below are the ones OBSERVED on live sessions during the
/// 2026-08-28 probe, in falling precedence; they are deliberately a small, cited set rather than
/// a guess at the full vocabulary, and anything unmatched yields `.unknown` instead of a default.
public enum AgentStateClassifier {
    /// Blocked beats everything: "finished" and "waiting on you" are otherwise indistinguishable,
    /// which is the exact ambiguity the out-of-tree hook existed to work around (ADR-0006 Context).
    /// CAPTURED, not guessed — and the history is worth carrying.
    ///
    /// This was `waiting-on-a-person` until 2026-08-31, taken from a live tail and shipped. That
    /// string is Claude Code's per-session TASK LABEL, rendered in a `⧉ <text>` slot: three live
    /// sessions carried three different values there, all IDLE, and two had no slot at all. It
    /// reported one session blocked for HOURS while it sat idle. A false amber is worse than a
    /// missing one — it calls the user to a window where nothing is wrong.
    ///
    /// The replacement was produced deliberately rather than found: a scratch Claude session was
    /// driven into an AskUserQuestion — which blocks on a human regardless of permission mode —
    /// and its tail read through the same ranged AX read the production adapter uses.
    ///
    /// A/B at the window this matcher actually uses (400 chars), 1 blocked vs 6 non-blocked:
    /// present on the blocked session, ABSENT on all six others.
    ///
    /// `Esc to cancel` rather than `Enter to select`, because it is the footer's common half.
    /// The trust-this-folder prompt renders `Enter to confirm · Esc to cancel` — READ from a
    /// screenshot, NOT captured live, so treat that second shape as expected-not-verified.
    ///
    /// ~~KNOWN LIMIT ... The 400-char window keeps it scoped to the live UI footer ... That is
    /// mitigation, not immunity.~~ **THE MITIGATION WAS TOO WEAK — measured 2026-09-01
    /// (EvanCNavarro/TermTile#34).** An idle session asked to print the string once was scored
    /// `.blocked` and would have been painted amber: 400 characters is several screen rows, so
    /// "unlikely" took exactly one sentence to defeat. Matching is now confined to the FINAL LINE
    /// — see `markerOnFinalLine`.
    static let blockedMarkers = ["Esc to cancel"]
    static let workingMarkers = ["esc to interrupt"]
    /// EMPTY, DELIBERATELY — see ADR-0006 finding 8. `shift+tab to cycle` was used here until
    /// 2026-08-31, when it was measured on a window that was ACTIVELY RUNNING a command and found
    /// present. It indicates "the input box is rendered", not "the agent is idle", so as a READY
    /// marker it paints a window green while work is still running. That is the worst failure this
    /// feature can have: a glance at green invites interrupting live work.
    ///
    /// No replacement is guessed at. Until a signal is MEASURED to distinguish idle from working,
    /// ready-detection is absent and those sessions classify `.unknown` — untinted rather than
    /// wrongly tinted. Tracked as EvanCNavarro/TermTile#6.
    static let readyMarkers: [String] = []

    /// How much of the tail is considered. The buffer holds up to ~44k chars of HISTORY
    /// (ADR-0006 finding 1), so matching the whole thing would let a marker from thousands of
    /// lines ago decide the CURRENT state. Only the live tail can speak for the present.
    public static let tailWindow = 400

    /// Collapses padding into single spaces so a marker matches the text as RENDERED.
    ///
    /// iTerm2's AX text carries `U+0000` where padding cells sit, so the on-screen
    /// "shift+tab to cycle" arrives as "shift+tab\0to\0cycle" (measured 2026-08-31 on a live
    /// session). Without this, every marker containing a space matched only intermittently —
    /// which is exactly why the hyphenated `waiting-on-a-person` always worked while the others
    /// flapped, and why 3 of 6 live panes read `.unknown`.
    ///
    /// NEWLINES ARE PRESERVED, deliberately. Folding them into spaces would let a marker's words
    /// sitting on two different rows fabricate a match that was never rendered as one phrase.
    static func normalize(_ raw: String) -> String {
        var out = String()
        out.reserveCapacity(raw.count)
        var lastWasSpace = false
        for character in raw {
            if character == "\n" {
                out.append(character)
                lastWasSpace = false
                continue
            }
            let isPadding = character == " "
                || character.unicodeScalars.allSatisfy { $0.value < 0x20 }
            if isPadding {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(character)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Whether any of `markers` appears on the LAST non-blank line of `text`.
    ///
    /// THE DISCRIMINATOR FOR EvanCNavarro/TermTile#34, measured across three live panes rather
    /// than reasoned about. A real blocking prompt REPLACES the status footer, so its
    /// `Esc to cancel` is the last text in the pane; text that merely mentions the phrase is
    /// followed by the footer that is still being drawn:
    ///
    ///     blocked (AskUserQuestion)   ... Enter to select   up/down to navigate   Esc to cancel
    ///     blocked (plan-mode question) ... n to add notes   Esc to cancel\n
    ///     displayed, NOT blocked       ... Esc to cancel \n ---- \n [Opus 5 ...] \n /rc
    ///
    /// Blank trailing lines are skipped rather than trimmed off the whole string: iTerm pads
    /// unused rows, and `normalize` has already turned those NUL cells into spaces, so a padded
    /// pane would otherwise present an empty final line and match nothing.
    ///
    /// Deliberately NOT keyed on the sibling affordances (`Enter to select`, `up/down to
    /// navigate`). That reads more semantic but binds to one UI family's footer wording, and both
    /// captures are the same family — a permission-approval prompt was never reproduced, so a
    /// wording rule would be fitted to two samples of one shape. Position is the weaker claim and
    /// the one the evidence actually supports.
    static func markerOnFinalLine(_ markers: [String], in text: String) -> Bool {
        guard let finalLine = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .last(where: { line in line.contains { $0 != " " } })
        else { return false }
        return markers.contains(where: finalLine.contains)
    }

    /// Full classification from one poll's evidence. Precedence is blocked > working > ready.
    ///
    /// READY IS RETURNED ONLY ON POSITIVE EVIDENCE OF STILLNESS — a delta that was actually
    /// measured. With no previous sample the result is `.unknown`, because "we have not looked
    /// twice yet" and "this session is idle" are different claims and only one of them is safe
    /// to paint green (ADR-0006 finding 8).
    public static func classify(_ evidence: StateEvidence) -> AgentState {
        classify(evidence, blocked: blockedMarkers)
    }

    static func classify(_ evidence: StateEvidence, blocked: [String]) -> AgentState {
        let tail = normalize(String(evidence.tail.suffix(tailWindow)))
        if markerOnFinalLine(blocked, in: tail) { return .blocked }
        if WorkingSignal.isWorking(evidence) { return .working }
        guard evidence.charCountDelta != nil else { return .unknown }
        return .ready
    }

    /// - Parameter scrollback: the session's full visible text, oldest first.
    public static func classify(scrollback: String) -> AgentState {
        classify(scrollback: scrollback, blocked: blockedMarkers)
    }

    /// Marker-set injectable so the BLOCKED semantics — precedence over working, and needing no
    /// delta — stay under test while `blockedMarkers` is empty (see its comment). Without this
    /// seam those properties would be unreachable, their tests would be deleted, and whoever adds
    /// a real marker for EvanCNavarro/TermTile#6 would be re-deriving the ordering from scratch.
    static func classify(scrollback: String, blocked: [String]) -> AgentState {
        let tail = normalize(String(scrollback.suffix(tailWindow)))
        if markerOnFinalLine(blocked, in: tail) { return .blocked }
        if workingMarkers.contains(where: tail.contains) { return .working }
        if readyMarkers.contains(where: tail.contains) { return .ready }
        return .unknown
    }
}

/// Everything one poll knows about a pane's state.
///
/// `charCountDelta` is `nil` on the FIRST poll of a session, when there is no previous sample to
/// compare against. That case classifies `.unknown` rather than `.ready`: with no delta the
/// evidence cannot separate idle from working, and guessing idle would paint a freshly-seen
/// working window green (ADR-0006 finding 8).
public struct StateEvidence: Equatable, Sendable {
    /// The short tail the markers are matched against.
    public let tail: String
    /// A wider window (~2000 chars) that reaches above the input box to the interrupt affordance.
    public let widerTail: String
    /// Change in the pane's character count since the previous poll; `nil` if there wasn't one.
    public let charCountDelta: Int?

    public init(tail: String, widerTail: String, charCountDelta: Int?) {
        self.tail = tail
        self.widerTail = widerTail
        self.charCountDelta = charCountDelta
    }
}

/// Decides whether a pane is actively working.
///
/// MEASURED 2026-08-31, 4 samples across 6 live sessions (24 observations), against ground truth
/// from the session-name glyph the out-of-tree poller uses (`✳` idle, spinner working):
///
///   signal                      working sessions caught   idle sessions misfired
///   character count moved       2 of 4 samples            0 of 16
///   wider tail has interrupt    7 of 8 samples            0 of 16
///   EITHER (this implementation) 8 of 8 samples           0 of 16
///
/// Neither alone suffices — a Claude session redrawing in place can hold its character count
/// steady while a Codex session's interrupt affordance sits outside the short tail. Together they
/// caught every working session and misfired on none.
public enum WorkingSignal {
    /// The affordance a terminal agent shows only while it is interruptible, i.e. while running.
    static let interruptMarkers = ["esc to interrupt"]

    public static func isWorking(_ evidence: StateEvidence) -> Bool {
        // ABSOLUTE value: the count DROPS when scrollback re-renders — an observed sample moved
        // -18. A `> 0` test would have scored that session idle and painted it green mid-run.
        if let delta = evidence.charCountDelta, delta != 0 { return true }
        let wider = AgentStateClassifier.normalize(evidence.widerTail)
        return interruptMarkers.contains(where: wider.contains)
    }
}

extension AgentState {
    /// What the diagnostics row shows. Mirrors `ReorderStrategy.displayName`.
    ///
    /// `.unknown` reads "not yet" rather than "unknown": from the user's side it is a pending
    /// answer, not a failure, and the row's reason line says which kind of pending it is.
    public var displayName: String {
        switch self {
        case .ready: return "Idle"
        case .working: return "Working"
        case .blocked: return "Waiting on you"
        case .unknown: return "Not yet"
        }
    }
}
