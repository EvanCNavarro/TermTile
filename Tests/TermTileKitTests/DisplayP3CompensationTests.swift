@testable import TermTileKit
import TermTileCore
import Testing

/// GROUND TRUTH, not prediction. Every pair below was written over OSC 1337 to a live scratch
/// iTerm2 window on 2026-09-01 and read back through AppleScript; the readback equalled the
/// target column. The suite exists so a refactor that changes the transform has to explain
/// itself against a terminal, not against a formula.
@Suite("Display P3 compensation")
struct DisplayP3CompensationTests {
    /// (target the user should SEE, value that must go into the escape sequence)
    static let measured: [(target: String, osc: String)] = [
        ("143C22", "264A30"),   // ready
        ("4A320F", "59421B"),   // blocked
        ("111417", "161A1E"),   // normal
        ("0E2B18", "1A3722"),   // readySubtle
        ("185634", "336646"),   // readyLouder
        ("1D7538", "41834E")    // readyLoudest
    ]

    private static func color(_ hex: String) -> TintColor {
        let v = UInt32(hex, radix: 16)!
        return TintColor(red: UInt8((v >> 16) & 0xFF), green: UInt8((v >> 8) & 0xFF), blue: UInt8(v & 0xFF))
    }

    @Test("every measured palette colour compensates to the value the terminal needs")
    func matchesMeasuredTable() {
        // A POSITIVE count first: an empty table would make every assertion below vacuous.
        #expect(Self.measured.count == 6)
        for pair in Self.measured {
            let got = DisplayP3Compensation.oscValue(for: Self.color(pair.target)).hex
            #expect(got == pair.osc, "target #\(pair.target): expected #\(pair.osc), got #\(got)")
        }
    }

    /// Guards the stub: an identity transform would pass nothing above, but this states the
    /// property directly so the failure reads as "not compensating" rather than "wrong number".
    @Test("compensation is not the identity")
    func isNotIdentity() {
        let ready = Self.color("143C22")
        #expect(DisplayP3Compensation.oscValue(for: ready) != ready)
    }

    /// Endpoints are shared by both spaces, so they must survive untouched. If these ever move,
    /// the white point assumption behind the whole transform has changed.
    @Test("black and white are unchanged")
    func endpointsUnchanged() {
        for hex in ["000000", "FFFFFF"] {
            #expect(DisplayP3Compensation.oscValue(for: Self.color(hex)).hex == hex)
        }
    }
}
