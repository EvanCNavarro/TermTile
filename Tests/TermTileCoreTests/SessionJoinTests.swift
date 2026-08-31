@testable import TermTileCore
import Testing

/// Fixtures mirror the six live windows measured on 2026-08-28 (ADR-0006 finding 3), where
/// badge N == ITERM_SESSION_ID window index + 1 held 6/6.
@Suite("Session join — resolves only when unambiguous")
struct SessionJoinTests {
    static let liveSessions = [
        TTYSessionSnapshot(tty: "/dev/ttys000", windowIndex: 0, tabIndex: 0, paneIndex: 0, cwd: "ChangeFabric"),
        TTYSessionSnapshot(tty: "/dev/ttys002", windowIndex: 1, tabIndex: 0, paneIndex: 0, cwd: "pushtext"),
        TTYSessionSnapshot(tty: "/dev/ttys001", windowIndex: 2, tabIndex: 0, paneIndex: 0, cwd: "evancnavarro"),
        TTYSessionSnapshot(tty: "/dev/ttys003", windowIndex: 3, tabIndex: 0, paneIndex: 0, cwd: "invela-marketing-suite"),
        TTYSessionSnapshot(tty: "/dev/ttys004", windowIndex: 4, tabIndex: 0, paneIndex: 0, cwd: "portfolio"),
        TTYSessionSnapshot(tty: "/dev/ttys005", windowIndex: 5, tabIndex: 0, paneIndex: 0, cwd: "termtile")
    ]

    @Test("badge N joins to window index N-1 — the six live windows")
    func badgeJoinsAllSixLiveWindows() {
        let panes = [
            AXPaneSnapshot(windowBadge: 1, cwd: "ChangeFabric"),
            AXPaneSnapshot(windowBadge: 2, cwd: "pushtext"),
            AXPaneSnapshot(windowBadge: 3, cwd: "evancnavarro"),
            AXPaneSnapshot(windowBadge: 4, cwd: "invela-marketing-suite"),
            AXPaneSnapshot(windowBadge: 5, cwd: "portfolio"),
            AXPaneSnapshot(windowBadge: 6, cwd: "termtile")
        ]
        let out = SessionJoin.resolve(panes: panes, sessions: Self.liveSessions)
        // Positive count FIRST: an empty result would run zero assertions below and "pass".
        #expect(out.count == 6)
        #expect(out == [
            .resolved(tty: "/dev/ttys000"), .resolved(tty: "/dev/ttys002"),
            .resolved(tty: "/dev/ttys001"), .resolved(tty: "/dev/ttys003"),
            .resolved(tty: "/dev/ttys004"), .resolved(tty: "/dev/ttys005")
        ])
    }

    /// THE CORE NEGATIVE CONTRACT. Past 9 windows the badge is nil (ADR-0006 finding 4), so the
    /// cwd fallback runs — and when two sessions share a cwd it CANNOT decide. Resolving here
    /// would paint one window with another's state.
    @Test("no badge + shared cwd is ambiguous, never a best guess")
    func sharedCwdWithoutBadgeIsAmbiguous() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 9, tabIndex: 0, paneIndex: 0, cwd: "shared"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 10, tabIndex: 0, paneIndex: 0, cwd: "shared")
        ]
        let panes = [AXPaneSnapshot(windowBadge: nil, cwd: "shared")]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .ambiguous(.cwdNotUnique))
    }

    @Test("no badge + unique cwd falls back and resolves")
    func uniqueCwdWithoutBadgeResolves() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 9, tabIndex: 0, paneIndex: 0, cwd: "alpha"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 10, tabIndex: 0, paneIndex: 0, cwd: "beta")
        ]
        let panes = [AXPaneSnapshot(windowBadge: nil, cwd: "beta")]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .resolved(tty: "/dev/ttys011"))
    }

    /// Splits CANNOT be resolved positionally. Measured 2026-08-31 with a 2x2 grid built by
    /// splitting the RIGHT side before the LEFT: iTerm assigned left-top=p0, right-top=p1,
    /// right-bottom=p2, left-bottom=p3 — CREATION order, not geometry. Row-major would have
    /// predicted p2/p3 swapped. So when a window holds several sessions, cwd is the only
    /// evidence, and identical cwds are unresolvable.
    @Test("split panes sharing a cwd are ambiguous — geometry cannot recover the pane index")
    func splitPanesSharingCwdAreAmbiguous() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 6, tabIndex: 0, paneIndex: 0, cwd: "same"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 6, tabIndex: 0, paneIndex: 1, cwd: "same")
        ]
        let panes = [AXPaneSnapshot(windowBadge: 7, cwd: "same")]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .ambiguous(.multipleCandidates))
    }

    @Test("split panes with distinct cwds resolve by cwd")
    func splitPanesWithDistinctCwdResolve() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys010", windowIndex: 6, tabIndex: 0, paneIndex: 0, cwd: "left"),
            TTYSessionSnapshot(tty: "/dev/ttys011", windowIndex: 6, tabIndex: 0, paneIndex: 1, cwd: "right")
        ]
        let panes = [
            AXPaneSnapshot(windowBadge: 7, cwd: "right"),
            AXPaneSnapshot(windowBadge: 7, cwd: "left")
        ]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 2)
        #expect(out == [.resolved(tty: "/dev/ttys011"), .resolved(tty: "/dev/ttys010")])
    }

    /// ADR-0006 finding 6: a background tab's session exists tty-side but has NO AX pane.
    /// The AX pane carries the ACTIVE session's own cwd, so when the tabs differ by cwd that
    /// is legitimate evidence — not a guess — and the visible pane resolves.
    @Test("a background-tab session with a distinct cwd never steals the visible pane")
    func backgroundTabWithDistinctCwdIsIgnored() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys006", windowIndex: 6, tabIndex: 0, paneIndex: 0, cwd: "visible"),
            TTYSessionSnapshot(tty: "/dev/ttys008", windowIndex: 6, tabIndex: 1, paneIndex: 0, cwd: "hidden")
        ]
        let panes = [AXPaneSnapshot(windowBadge: 7, cwd: "visible")]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .resolved(tty: "/dev/ttys006"))
        #expect(!out.contains(.resolved(tty: "/dev/ttys008")),
                "the background-tab tty must never be joined to a visible pane")
    }

    /// The honest half of the same case. When two TABS share a cwd, nothing on the tty side
    /// says which is active, so there is no evidence to pick with. Preferring the lower tab
    /// index would resolve every time and be silently wrong some of the time.
    @Test("two tabs sharing a cwd are ambiguous, not resolved by tab order")
    func backgroundTabSharingCwdIsAmbiguous() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys006", windowIndex: 6, tabIndex: 0, paneIndex: 0, cwd: "proj"),
            TTYSessionSnapshot(tty: "/dev/ttys008", windowIndex: 6, tabIndex: 1, paneIndex: 0, cwd: "proj")
        ]
        let panes = [AXPaneSnapshot(windowBadge: 7, cwd: "proj")]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .ambiguous(.multipleCandidates))
    }

    @Test("a badge pointing at a window with no sessions is ambiguous")
    func badgeWithNoSessionsIsAmbiguous() {
        let panes = [AXPaneSnapshot(windowBadge: 9, cwd: "ghost")]
        let out = SessionJoin.resolve(panes: panes, sessions: Self.liveSessions)
        #expect(out.count == 1)
        #expect(out.first == .ambiguous(.noCandidate))
    }

    @Test("no panes yields no outcomes")
    func emptyInput() {
        #expect(SessionJoin.resolve(panes: [], sessions: Self.liveSessions).isEmpty)
    }
}
