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

/// THE PROOF FOR EvanCNavarro/TermTile#29. The unit tests show the writer emits a compensated
/// hex; they cannot show the terminal then RENDERS the requested one. This drives the real
/// adapter at a real session and reads the colour back out of iTerm2.
///
///     TT_LIVE_AX=1 TT_LIVE_TTY=/dev/ttysNNN swift test --filter PaletteRendersAsRequestedLiveTests
///
/// RUN IT ALONE. Both live suites drive the SAME `TT_LIVE_TTY`, so a filter that selects both
/// lets `OSCColorWriterLiveTests` repaint the session between this one's write and its readback
/// — observed 2026-09-01, reporting `#6A1B9A` (the other suite's probe colour) as `ready`.
struct PaletteRendersAsRequestedLiveTests {
    static var target: String? { OSCColorWriterLiveTests.target }

    /// Reads `background color` for the session on `tty`. Returns nil rather than a default:
    /// an unreadable colour must FAIL the test, never silently score as a match.
    static func readBackground(tty: String) -> (Int, Int, Int)? {
        let script = """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then return background color of s
              end repeat
            end repeat
          end repeat
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // Parse the three components SEPARATELY. "0, 12253, 6093" concatenated is ambiguous —
        // it reads equally as (0,12253,6093) or (0,1225,36093), and eyeballing it that way
        // produced two wrong readings earlier in this investigation.
        let parts = (String(data: data, encoding: .utf8) ?? "")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count == 3 else { return nil }
        // ROUND, never truncate. Integer `n * 255 / 65535` floors, which biased every channel
        // low by one and made all six palette colours report drift 1 — an instrument error that
        // the tolerance would have hidden, and that a real 1-LSB regression would then hide behind.
        func to8(_ n: Int) -> Int { (n * 255 + 32767) / 65535 }
        return (to8(parts[0]), to8(parts[1]), to8(parts[2]))
    }

    @Test("every palette colour renders as the hex it asks for", .enabled(if: target != nil))
    func paletteRendersAsRequested() async throws {
        let tty = try #require(Self.target)
        let writer = OSCColorWriter()
        let palette: [(String, TintColor)] = [
            ("ready", TintPalette.ready), ("blocked", TintPalette.blocked),
            ("normal", TintPalette.normal), ("bold", TintPalette.readyBold)
        ]
        #expect(palette.count == 4)
        for (name, colour) in palette {
            #expect(await writer.setBackground(colour, onTTY: tty), "\(name): the write failed")
            try await Task.sleep(nanoseconds: 500_000_000)
            let got = try #require(Self.readBackground(tty: tty), "\(name): readback failed")
            let want = (Int(colour.red), Int(colour.green), Int(colour.blue))
            let drift = max(abs(got.0 - want.0), max(abs(got.1 - want.1), abs(got.2 - want.2)))
            // EXACT. The `rgb:` prefix sends the palette hex unconverted, so there is no
            // quantisation step left to absorb — a drift of even 1 now means something moved.
            #expect(drift == 0,
                    "\(name) asked for #\(colour.hex), rendered (\(got.0),\(got.1),\(got.2)) — drift \(drift)")
            print("LIVE-RENDER \(name)\trequested #\(colour.hex)\tgot (\(got.0),\(got.1),\(got.2))\tdrift \(drift)")
        }
    }
}
