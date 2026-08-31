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
            AXPaneSnapshot(windowBadge: 1, cwd: "ChangeFabric", paneOrdinal: 0),
            AXPaneSnapshot(windowBadge: 2, cwd: "pushtext", paneOrdinal: 0),
            AXPaneSnapshot(windowBadge: 3, cwd: "evancnavarro", paneOrdinal: 0),
            AXPaneSnapshot(windowBadge: 4, cwd: "invela-marketing-suite", paneOrdinal: 0),
            AXPaneSnapshot(windowBadge: 5, cwd: "portfolio", paneOrdinal: 0),
            AXPaneSnapshot(windowBadge: 6, cwd: "termtile", paneOrdinal: 0)
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
        let panes = [AXPaneSnapshot(windowBadge: nil, cwd: "shared", paneOrdinal: 0)]
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
        let panes = [AXPaneSnapshot(windowBadge: nil, cwd: "beta", paneOrdinal: 0)]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .resolved(tty: "/dev/ttys011"))
    }

    /// Splits: two panes in one window's active tab, ordered left-to-right. Measured
    /// 2026-08-28 — area[0] x=578 was p0/ttys006, area[1] x=912 was p1/ttys007.
    @Test("split panes map by ordinal within the badged window")
    func splitPanesMapByOrdinal() {
        let sessions = [
            TTYSessionSnapshot(tty: "/dev/ttys006", windowIndex: 6, tabIndex: 0, paneIndex: 0, cwd: "evancnavarro"),
            TTYSessionSnapshot(tty: "/dev/ttys007", windowIndex: 6, tabIndex: 0, paneIndex: 1, cwd: "evancnavarro")
        ]
        let panes = [
            AXPaneSnapshot(windowBadge: 7, cwd: "evancnavarro", paneOrdinal: 0),
            AXPaneSnapshot(windowBadge: 7, cwd: "evancnavarro", paneOrdinal: 1)
        ]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 2)
        #expect(out == [.resolved(tty: "/dev/ttys006"), .resolved(tty: "/dev/ttys007")])
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
        let panes = [AXPaneSnapshot(windowBadge: 7, cwd: "visible", paneOrdinal: 0)]
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
        let panes = [AXPaneSnapshot(windowBadge: 7, cwd: "proj", paneOrdinal: 0)]
        let out = SessionJoin.resolve(panes: panes, sessions: sessions)
        #expect(out.count == 1)
        #expect(out.first == .ambiguous(.multipleCandidates))
    }

    @Test("a badge pointing at a window with no sessions is ambiguous")
    func badgeWithNoSessionsIsAmbiguous() {
        let panes = [AXPaneSnapshot(windowBadge: 9, cwd: "ghost", paneOrdinal: 0)]
        let out = SessionJoin.resolve(panes: panes, sessions: Self.liveSessions)
        #expect(out.count == 1)
        #expect(out.first == .ambiguous(.noCandidate))
    }

    @Test("no panes yields no outcomes")
    func emptyInput() {
        #expect(SessionJoin.resolve(panes: [], sessions: Self.liveSessions).isEmpty)
    }
}
