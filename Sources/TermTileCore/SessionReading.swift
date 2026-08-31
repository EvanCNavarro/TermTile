import Foundation

/// Parses iTerm2's window-number badge, the primary join key (ADR-0006 finding 3).
///
/// The badge renders in the title bar as an `AXStaticText` reading `⌥⌘N`, and N is the
/// `ITERM_SESSION_ID` window index PLUS ONE. Parsing is deliberately STRICT: this string is
/// picked out of a window's static-text children, which also carry the window title and any
/// other label iTerm chooses to put there. A lenient parser that accepted a bare digit would
/// happily read a window titled "3" as badge 3 and join it to the wrong session.
public enum ITermBadge {
    /// iTerm only assigns ⌥⌘1 through ⌥⌘9 — measured at 11 open windows, exactly 9 carried a
    /// badge (ADR-0006 finding 4). Zero is rejected because badge-1 would yield window index
    /// -1, a bogus lookup that must never reach the join.
    public static let validRange = 1...9

    public static func parse(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let prefix = "\u{2325}\u{2318}"          // ⌥⌘
        guard raw.hasPrefix(prefix) else { return nil }
        let digits = raw.dropFirst(prefix.count)
        guard digits.count == 1, let n = Int(digits), validRange.contains(n) else { return nil }
        return n
    }
}

/// One visible pane: everything a single poll needs about it.
///
/// The tail is deliberately SHORT. Measured 2026-08-31: a full `AXValue` read of six live
/// sessions pulled 253,773 characters in ~65 ms, while a ranged tail read pulled 2,390 in
/// ~41 ms. The speed difference is minor because AX cost is dominated by IPC round-trips, but
/// the DATA difference is the point — ADR-0006 commits to reading window contents as narrowly
/// as the job allows, and a quarter-megabyte of the user's terminal in app memory is not that.
public struct ObservedPane: Equatable, Sendable {
    public let snapshot: AXPaneSnapshot
    /// The last few hundred characters of the pane's scrollback — the classifier's whole input.
    public let scrollbackTail: String

    public init(snapshot: AXPaneSnapshot, scrollbackTail: String) {
        self.snapshot = snapshot
        self.scrollbackTail = scrollbackTail
    }
}
