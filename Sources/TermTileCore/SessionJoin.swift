import Foundation

/// One pane as seen through the Accessibility API.
///
/// `windowBadge` is the iTerm window-number badge (`⌥⌘N` -> N). It is `nil` whenever the badge is
/// absent, which ADR-0006 finding 4 pins to a hard ceiling: at 11 open windows exactly 9 carried
/// one. Finding 5 adds that it renders from iTerm's DEFAULT, not a user setting, but remains
/// user-disableable — so `nil` is an ordinary case, never an error.
public struct AXPaneSnapshot: Equatable, Sendable {
    public let windowBadge: Int?
    public let cwd: String

    public init(windowBadge: Int?, cwd: String) {
        self.windowBadge = windowBadge
        self.cwd = cwd
    }
}

/// One session as seen from the tty side, via `ITERM_SESSION_ID=w<W>t<T>p<P>`.
public struct TTYSessionSnapshot: Equatable, Sendable {
    public let tty: String
    public let windowIndex: Int
    public let tabIndex: Int
    public let paneIndex: Int
    public let cwd: String

    public init(tty: String, windowIndex: Int, tabIndex: Int, paneIndex: Int, cwd: String) {
        self.tty = tty
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.paneIndex = paneIndex
        self.cwd = cwd
    }
}

/// Why a pane could not be resolved to exactly one tty.
public enum AmbiguityReason: String, Equatable, Sendable {
    /// No badge, and the cwd fallback matched more than one session.
    case cwdNotUnique
    /// Nothing matched at all.
    case noCandidate
    /// The badge resolved a window, but more than one session there fits the pane.
    case multipleCandidates
}

/// The result of joining one AX pane to the tty side.
public enum JoinOutcome: Equatable, Sendable {
    case resolved(tty: String)
    case ambiguous(AmbiguityReason)
}

/// Joins AX panes to tty sessions.
///
/// PURE (ADR-0001 rule 1). The contract that matters is the NEGATIVE one: an unresolvable pane
/// yields `.ambiguous` and the caller leaves it at its normal colour. Resolving it to a
/// best-guess tty would paint one window with another window's state.
public enum SessionJoin {
    /// - Returns: one outcome per pane, in the order given.
    public static func resolve(
        panes: [AXPaneSnapshot],
        sessions: [TTYSessionSnapshot]
    ) -> [JoinOutcome] {
        panes.map { pane in resolve(pane: pane, sessions: sessions) }
    }

    /// The badge is the primary key when present (ADR-0006 finding 3); cwd is the fallback
    /// when it is not (finding 4/5). Neither is allowed to guess: every path that cannot
    /// narrow to exactly one session returns `.ambiguous`.
    private static func resolve(
        pane: AXPaneSnapshot,
        sessions: [TTYSessionSnapshot]
    ) -> JoinOutcome {
        guard let badge = pane.windowBadge else {
            // No badge. cwd is all that is left, and it is only usable if it is unique.
            let byCwd = sessions.filter { $0.cwd == pane.cwd }
            guard let only = byCwd.first else { return .ambiguous(.noCandidate) }
            return byCwd.count == 1 ? .resolved(tty: only.tty) : .ambiguous(.cwdNotUnique)
        }

        // Badge N addresses ITERM_SESSION_ID window index N-1.
        let inWindow = sessions.filter { $0.windowIndex == badge - 1 }
        if inWindow.isEmpty { return .ambiguous(.noCandidate) }

        if inWindow.count == 1, let only = inWindow.first { return .resolved(tty: only.tty) }

        // More than one session in that window means SPLITS, TABS, or both. Neither is
        // resolvable positionally: AX shows only the active tab (ADR-0006 finding 6), and the
        // `p` index is a CREATION COUNTER, not a position (finding 6b, measured 2026-08-31) —
        // so pane geometry cannot recover it. cwd is the only remaining evidence, and it is
        // real evidence because the AX pane carries its OWN session's cwd. If cwd cannot
        // separate them, the honest answer is ambiguous.
        let byCwd = inWindow.filter { $0.cwd == pane.cwd }
        guard byCwd.count == 1, let only = byCwd.first else {
            return .ambiguous(.multipleCandidates)
        }
        return .resolved(tty: only.tty)
    }
}
