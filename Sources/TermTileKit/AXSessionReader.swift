@preconcurrency import ApplicationServices
import AppKit
import Foundation
import TermTileCore

/// The PRODUCTION `SessionReading` adapter (ADR-0006 Tier 1 read path).
///
/// Reads state through the Accessibility grant TermTile already holds — no Apple Events, no
/// entitlement, no TCC prompt beyond the one tiling already requires.
///
/// An `actor` so it satisfies the `Sendable` port; every `AXUIElement` stays inside an isolated
/// method and only `Sendable` value types cross the boundary.
public actor AXSessionReader: SessionReading {
    private let bundleID: String
    /// How many trailing characters to pull per pane. Matches the classifier's own window so the
    /// two agree about what "the tail" means.
    private let tailLength: Int

    public init(bundleID: String, tailLength: Int = ObservedPane.tailLength) {
        self.bundleID = bundleID
        self.tailLength = tailLength
    }

    public func visiblePanes() async -> [ObservedPane] {
        guard let appEl = appElement() else { return [] }
        let windows = (copyAttr(appEl, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.flatMap { panes(in: $0) }
    }

    private func appElement() -> AXUIElement? {
        let apps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .map(AXReadableApplication.init)
        guard let app = TargetRunningApplicationResolver.preferred(
            bundleID: bundleID,
            in: apps,
            bundleIdentifier: \.bundleIdentifier,
            isRegular: \.isRegular
        ) else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// One `ObservedPane` per visible text area in `window`.
    private func panes(in window: AXUIElement) -> [ObservedPane] {
        let badge = ITermBadge.parse(badgeText(of: window))
        return textAreas(under: window).compactMap { area in
            guard let cwd = SessionDocument.cwdName(
                fromAXDocument: copyAttr(area, "AXDocument") as? String
            ) else { return nil }   // no cwd = nothing the join could match on
            return ObservedPane(
                snapshot: AXPaneSnapshot(windowBadge: badge, cwd: cwd),
                scrollbackTail: tail(of: area),
                characterCount: copyAttr(area, "AXNumberOfCharacters") as? Int ?? 0
            )
        }
    }

    /// The window-number badge, which iTerm renders as a direct `AXStaticText` child reading
    /// `⌥⌘N`. The window TITLE is also a static-text child, which is exactly why `ITermBadge`
    /// parses strictly rather than hunting for a digit.
    private func badgeText(of window: AXUIElement) -> String? {
        let children = (copyAttr(window, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        for child in children where (copyAttr(child, kAXRoleAttribute) as? String) == kAXStaticTextRole {
            if let text = copyAttr(child, kAXValueAttribute) as? String,
               ITermBadge.parse(text) != nil {
                return text
            }
        }
        return nil
    }

    /// Text areas are nested window -> group -> split group -> scroll area -> text area, and a
    /// split adds another level, so this walks rather than assuming a fixed depth. Bounded to
    /// keep a pathological tree from becoming an unbounded traversal on a timer.
    private func textAreas(under element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth <= 8 else { return [] }
        if (copyAttr(element, kAXRoleAttribute) as? String) == kAXTextAreaRole { return [element] }
        let children = (copyAttr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        return children.flatMap { textAreas(under: $0, depth: depth + 1) }
    }

    /// The last `tailLength` characters, read as a RANGE rather than by pulling `AXValue`.
    ///
    /// Measured 2026-08-31 across six live sessions: a full `AXValue` read pulled 253,773
    /// characters, the ranged read 2,390. The time difference is minor (~65ms vs ~41ms; AX cost
    /// is IPC-bound) — the reason is ADR-0006's privacy commitment. TermTile has no business
    /// holding a quarter-megabyte of someone's terminal in memory to answer a three-way question.
    ///
    /// UNITS: `AXNumberOfCharacters` and `AXStringForRange` count UTF-16 code units, while Swift's
    /// `String.count` counts graphemes. Measured on a live session: 40,210 UTF-16 vs 40,208
    /// graphemes, so a 400-unit request returned 398 characters. The effective window is therefore
    /// between `tailLength/2` and `tailLength` graphemes. That is fine — the markers sit at the very
    /// end of the buffer — but it is an asymmetry, not an accident, and the live test asserts the
    /// result never EXCEEDS the window so a regression to a full `AXValue` pull would fail loudly.
    ///
    /// Returns "" on any failure, which classifies as `.unknown` and leaves the session untinted.
    private func tail(of area: AXUIElement) -> String {
        guard let total = copyAttr(area, "AXNumberOfCharacters") as? Int, total > 0 else { return "" }
        let length = min(tailLength, total)
        var range = CFRange(location: total - length, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return "" }
        return copyParamAttr(area, "AXStringForRange", rangeValue) as? String ?? ""
    }
}

private struct AXReadableApplication {
    let app: NSRunningApplication

    var bundleIdentifier: String? { app.bundleIdentifier }
    var isRegular: Bool { app.activationPolicy == .regular }
    var processIdentifier: pid_t { app.processIdentifier }
}
