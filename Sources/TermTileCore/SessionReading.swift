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

    /// The tail of the pane's scrollback — the classifier's whole textual input.
    ///
    /// WIDENED from 400 to `ObservedPane.tailLength` on 2026-08-31, and this is a deliberate
    /// change to how much of the user's terminal the app reads. ADR-0006 finding 9 measured the
    /// interrupt affordance that distinguishes working from idle sitting ABOVE the input box,
    /// outside a 400-character window. Ready-detection does not work without it. The ADR's
    /// commitment is to read as narrowly as the job allows, not to a particular number, so the
    /// number moved when the job was measured — but it moved by evidence, and no further.
    public let scrollbackTail: String

    /// The pane's total character count, used ONLY to detect movement between polls. A count is
    /// not content: it carries no terminal text, and comparing two of them is what lets ready
    /// require a MEASURED delta rather than an assumed one.
    public let characterCount: Int

    public init(snapshot: AXPaneSnapshot, scrollbackTail: String, characterCount: Int) {
        self.snapshot = snapshot
        self.scrollbackTail = scrollbackTail
        self.characterCount = characterCount
    }

    /// How much tail one poll reads. Wide enough for the interrupt affordance (finding 9), and
    /// still ~5% of the ~44k a full `AXValue` pull would take.
    public static let tailLength = 2000
}

/// Extracts the directory NAME from an iTerm session's `AXDocument`.
///
/// The attribute arrives as a file URL carrying a host, e.g.
/// `file://evancnavarro@MacBookPro.lan/Users/evancnavarro/Developer/invela-marketing-suite`
/// (observed 2026-08-28). The join compares this against the basename of the tty-side
/// process cwd, so only the last component matters — and it MUST be percent-decoded, because
/// a directory with a space arrives as `%20` and would never match its tty-side twin.
public enum SessionDocument {
    public static func cwdName(fromAXDocument raw: String?) -> String? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return nil }
        // `lastPathComponent` percent-DECODES and tolerates a trailing slash; the root yields
        // "/", which is not a directory name the join can use.
        let name = url.standardizedFileURL.lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        return name
    }
}
