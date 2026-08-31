@testable import TermTileCore
import Testing

@Suite("Tint palette and OSC sequence")
struct TintColorTests {
    @Test("hex matches the palette the replaced tool used")
    func hex() {
        #expect(TintPalette.ready.hex == "143C22")
        #expect(TintPalette.blocked.hex == "4A320F")
        #expect(TintPalette.normal.hex == "111417")
    }

    @Test("presets carry over verbatim")
    func presets() {
        #expect(TintPalette.readySubtle.hex == "0E2B18")
        #expect(TintPalette.readyLouder.hex == "185634")
        #expect(TintPalette.readyLoudest.hex == "1D7538")
    }

    @Test("low components keep both hex digits")
    func padding() {
        #expect(TintColor(red: 0, green: 1, blue: 15).hex == "00010F")
    }

    /// `.unknown` must map to NO colour. If it ever maps to one, an unrecognised state starts
    /// getting painted, which is the failure the whole classifier design avoids.
    @Test("unknown maps to no colour at all")
    func unknownPaintsNothing() {
        #expect(TintPalette.color(for: .unknown) == nil)
        #expect(TintPalette.color(for: .ready) == TintPalette.ready)
        #expect(TintPalette.color(for: .blocked) == TintPalette.blocked)
        #expect(TintPalette.color(for: .working) == TintPalette.normal)
    }

    @Test("a chosen ready intensity is honoured")
    func readyIntensity() {
        #expect(TintPalette.color(for: .ready, ready: TintPalette.readyLoudest)
            == TintPalette.readyLoudest)
    }

    /// The exact bytes proven against live iTerm2 on 2026-08-28.
    @Test("the escape sequence is OSC 1337 SetColors terminated by BEL")
    func sequence() {
        #expect(OSCSequence.setBackground(TintPalette.ready) == "\u{1B}]1337;SetColors=bg=143C22\u{07}")
    }
}

@Suite("TTY path validation — this writes raw bytes to a path")
struct TTYPathValidationTests {
    @Test("real terminal devices are accepted")
    func accepts() {
        #expect(OSCSequence.isWritableTerminalDevice("/dev/ttys000"))
        #expect(OSCSequence.isWritableTerminalDevice("/dev/ttys005"))
        #expect(OSCSequence.isWritableTerminalDevice("/dev/ttys123"))
    }

    /// The reason this function exists. The tty string is derived from parsed `ps` output; a
    /// malformed or hostile value must not become a write target.
    @Test("arbitrary paths are refused")
    func refusesArbitraryPaths() {
        #expect(!OSCSequence.isWritableTerminalDevice("/etc/passwd"))
        #expect(!OSCSequence.isWritableTerminalDevice("/Users/evancnavarro/.claude/.env"))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/null"))
    }

    @Test("traversal cannot smuggle a path through")
    func refusesTraversal() {
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/../etc/passwd"))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/ttys000/../../etc/passwd"))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/ttys000\u{0}/etc/passwd"))
    }

    @Test("near-misses are refused")
    func refusesNearMisses() {
        #expect(!OSCSequence.isWritableTerminalDevice(""))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/tty"))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/ttys"))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/ttysABC"))
        #expect(!OSCSequence.isWritableTerminalDevice("ttys000"))
        #expect(!OSCSequence.isWritableTerminalDevice(" /dev/ttys000"))
        #expect(!OSCSequence.isWritableTerminalDevice("/dev/ttys000 "))
    }
}
