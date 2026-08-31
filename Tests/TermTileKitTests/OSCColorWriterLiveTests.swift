import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// LIVE PROOF of the real writer against a real terminal device.
///
/// Opt-in twice over: `TT_LIVE_AX=1` plus `TT_LIVE_TTY=/dev/ttysNNN`, because this one has a
/// VISIBLE side effect on someone's terminal. It writes a distinctive colour that the caller
/// then reads back out of iTerm2; without the readback this test would only prove that a write
/// call returned true, which is not the same as the colour having changed.
///
///     TT_LIVE_AX=1 TT_LIVE_TTY=/dev/ttys005 swift test --filter OSCColorWriterLiveTests
struct OSCColorWriterLiveTests {
    static var target: String? {
        guard ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1" else { return nil }
        return ProcessInfo.processInfo.environment["TT_LIVE_TTY"]
    }

    /// A colour no palette entry uses, so a readback matching it cannot be a coincidence.
    static let probeColor = TintColor(red: 0x6A, green: 0x1B, blue: 0x9A)

    @Test("writes a real OSC sequence to a real tty", .enabled(if: target != nil))
    func writesLive() async throws {
        let tty = try #require(Self.target)
        #expect(OSCSequence.isWritableTerminalDevice(tty), "TT_LIVE_TTY is not a tty device")

        let writer = OSCColorWriter()
        let wrote = await writer.setBackground(Self.probeColor, onTTY: tty)
        #expect(wrote, "the real writer reported failure writing to \(tty)")
        print("LIVE-WRITE  \(tty)  bg=#\(Self.probeColor.hex)  wrote=\(wrote)")

        // Refusal must hold on the real writer too, not just behind the injected double.
        let refused = await writer.setBackground(Self.probeColor, onTTY: "/etc/passwd")
        #expect(!refused, "the REAL writer accepted /etc/passwd")
        print("LIVE-WRITE  /etc/passwd refused=\(!refused)")
    }
}
