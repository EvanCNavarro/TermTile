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

@Suite("AXDocument -> cwd name")
struct SessionDocumentTests {
    /// Verbatim from the 2026-08-28 probe.
    @Test("the observed AXDocument form yields the directory name")
    func observedForm() {
        let raw = "file://evancnavarro@MacBookPro.lan/Users/evancnavarro/Developer/invela-marketing-suite"
        #expect(SessionDocument.cwdName(fromAXDocument: raw) == "invela-marketing-suite")
    }

    @Test("a hostless file URL also works")
    func hostless() {
        #expect(SessionDocument.cwdName(fromAXDocument: "file:///Users/evancnavarro/Developer/termtile")
            == "termtile")
    }

    /// The one that bites: a directory with a space arrives percent-encoded and would never
    /// match the tty-side basename unless it is decoded.
    @Test("percent-encoding is decoded so it can match the tty-side basename")
    func percentDecoded() {
        let raw = "file:///Users/evancnavarro/Developer/My%20Project"
        #expect(SessionDocument.cwdName(fromAXDocument: raw) == "My Project")
    }

    @Test("a trailing slash does not swallow the name")
    func trailingSlash() {
        #expect(SessionDocument.cwdName(fromAXDocument: "file:///Users/evancnavarro/Developer/portfolio/")
            == "portfolio")
    }

    @Test("absent or empty yields nil, never an empty string")
    func absent() {
        #expect(SessionDocument.cwdName(fromAXDocument: nil) == nil)
        #expect(SessionDocument.cwdName(fromAXDocument: "") == nil)
    }

    @Test("the filesystem root has no meaningful name")
    func root() {
        #expect(SessionDocument.cwdName(fromAXDocument: "file:///") == nil)
    }
}
