@testable import TermTileCore
import Testing

@Suite("iTerm badge parsing — strict, because the source is a bag of static text")
struct ITermBadgeTests {
    @Test("the observed badge format parses to its number")
    func observedFormat() {
        #expect(ITermBadge.parse("⌥⌘1") == 1)
        #expect(ITermBadge.parse("⌥⌘6") == 6)
        #expect(ITermBadge.parse("⌥⌘9") == 9)
    }

    @Test("absent badge is nil, not an error — it is an ordinary case past 9 windows")
    func absent() {
        #expect(ITermBadge.parse(nil) == nil)
        #expect(ITermBadge.parse("") == nil)
    }

    /// The reason parsing is strict. These strings all appear as AXStaticText on a real window.
    @Test("window titles and bare digits are NOT badges")
    func doesNotMatchTitles() {
        #expect(ITermBadge.parse("Bluebox") == nil)
        #expect(ITermBadge.parse("3") == nil, "a window titled 3 must not read as badge 3")
        #expect(ITermBadge.parse("⌘6") == nil, "missing the option glyph is not the badge format")
        #expect(ITermBadge.parse("PR-Check") == nil)
    }

    /// badge-1 becomes the window index, so 0 would produce -1 and look up a window that
    /// cannot exist. Reject at the parse boundary rather than defending downstream.
    @Test("zero is rejected — badge-1 would be a negative window index")
    func rejectsZero() {
        #expect(ITermBadge.parse("⌥⌘0") == nil)
    }

    @Test("out-of-range and multi-digit are rejected")
    func rejectsOutOfRange() {
        #expect(ITermBadge.parse("⌥⌘10") == nil)
        #expect(ITermBadge.parse("⌥⌘99") == nil)
    }
}
