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

    /// TWO shades since 2026-09-01. The assertion that matters is not the hex — it is that the
    /// two are far enough apart to be told apart, and that BOTH clear `normal` by a wide margin.
    /// A test pinning only the hexes would pass on two identical greens.
    @Test("the two ready shades are distinct from each other and from normal")
    func presets() {
        #expect(TintPalette.ready.hex == "143C22")
        #expect(TintPalette.readyBold.hex == "1D7538")
        #expect(TintPalette.ready != TintPalette.readyBold)
        #expect(TintPalette.ready != TintPalette.normal)
        #expect(TintPalette.readyBold != TintPalette.normal)
        #expect(Set(ReadyIntensity.allCases.map(\.color.hex)).count == ReadyIntensity.allCases.count,
                "two intensities resolved to the same colour")
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
        #expect(TintPalette.color(for: .ready, ready: TintPalette.readyBold)
            == TintPalette.readyBold)
    }

    /// The exact bytes proven against live iTerm2 on 2026-08-28.
    @Test("the escape sequence is OSC 1337 SetColors terminated by BEL")
    func sequence() {
        #expect(OSCSequence.setBackground(TintPalette.ready) == "\u{1B}]1337;SetColors=bg=rgb:143C22\u{07}")
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
