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
    static let readyMarkers = ["shift+tab to cycle"]

    /// How much of the tail is considered. The buffer holds up to ~44k chars of HISTORY
    /// (ADR-0006 finding 1), so matching the whole thing would let a marker from thousands of
    /// lines ago decide the CURRENT state. Only the live tail can speak for the present.
    public static let tailWindow = 400

    /// - Parameter scrollback: the session's full visible text, oldest first.
    public static func classify(scrollback: String) -> AgentState {
        let tail = String(scrollback.suffix(tailWindow))
        if blockedMarkers.contains(where: tail.contains) { return .blocked }
        if workingMarkers.contains(where: tail.contains) { return .working }
        if readyMarkers.contains(where: tail.contains) { return .ready }
        return .unknown
    }
}
