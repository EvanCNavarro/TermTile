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
    static let blockedMarkers = ["waiting-on-a-person"]
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

    /// - Parameter scrollback: the session's full visible text, oldest first.
    public static func classify(scrollback: String) -> AgentState {
        let tail = normalize(String(scrollback.suffix(tailWindow)))
        if blockedMarkers.contains(where: tail.contains) { return .blocked }
        if workingMarkers.contains(where: tail.contains) { return .working }
        if readyMarkers.contains(where: tail.contains) { return .ready }
        return .unknown
    }
}
