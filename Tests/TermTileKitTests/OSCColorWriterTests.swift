@testable import TermTileKit
import TermTileCore
import Testing

/// The double records instead of writing, so the suite never touches a real terminal.
actor RecordingDeviceWriter {
    private(set) var writes: [(path: String, bytes: String)] = []
    func record(_ path: String, _ bytes: String) { writes.append((path, bytes)) }
}

@Suite("OSC colour writer")
struct OSCColorWriterTests {
    @Test("writes the OSC sequence to a valid tty")
    func writesSequence() async {
        let recorder = RecordingDeviceWriter()
        let writer = OSCColorWriter { path, bytes in
            Task { await recorder.record(path, bytes) }
            return true
        }
        let ok = await writer.setBackground(TintPalette.ready, onTTY: "/dev/ttys005")
        #expect(ok)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let writes = await recorder.writes
        #expect(writes.count == 1)
        #expect(writes.first?.path == "/dev/ttys005")
        // COMPENSATED, not the palette hex: iTerm reads an OSC triple as Display P3 while the
        // palette is authored in Generic RGB. #264A30 is the value measured on a live terminal
        // to render as #143C22 (EvanCNavarro/TermTile#29).
        #expect(writes.first?.bytes == "\u{1B}]1337;SetColors=bg=264A30\u{07}")
    }

    /// THE SAFETY TEST. An invalid path must be refused BEFORE the device writer is reached —
    /// not refused inside it, where a future refactor could drop the check.
    @Test("an invalid tty is refused and the device writer is never called")
    func refusesInvalidPath() async {
        let recorder = RecordingDeviceWriter()
        let writer = OSCColorWriter { path, bytes in
            Task { await recorder.record(path, bytes) }
            return true
        }
        for bad in ["/etc/passwd", "/dev/../etc/passwd", "/dev/ttysABC", "", "/dev/null"] {
            let ok = await writer.setBackground(TintPalette.blocked, onTTY: bad)
            #expect(!ok, "accepted a write to \(bad)")
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await recorder.writes.isEmpty, "the device writer was reached with a bad path")
    }

    @Test("a failing device write reports failure rather than claiming success")
    func propagatesFailure() async {
        let writer = OSCColorWriter { _, _ in false }
        #expect(!(await writer.setBackground(TintPalette.normal, onTTY: "/dev/ttys000")))
    }

    /// Each state paints its own colour, and unknown paints nothing.
    @Test("each state maps to its palette colour end to end")
    func statesMapToColours() async {
        let recorder = RecordingDeviceWriter()
        let writer = OSCColorWriter { path, bytes in
            Task { await recorder.record(path, bytes) }
            return true
        }
        for (state, tty) in [(AgentState.ready, "/dev/ttys001"),
                             (.blocked, "/dev/ttys002"),
                             (.working, "/dev/ttys003"),
                             (.unknown, "/dev/ttys004")] {
            if let colour = TintPalette.color(for: state) {
                await writer.setBackground(colour, onTTY: tty)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let writes = await recorder.writes
        #expect(writes.count == 3, "unknown must not produce a write")
        #expect(writes.contains { $0.bytes.contains("264A30") })   // renders as #143C22
        #expect(writes.contains { $0.bytes.contains("59421B") })   // renders as #4A320F
        #expect(writes.contains { $0.bytes.contains("161A1E") })   // renders as #111417
        #expect(!writes.contains { $0.bytes.contains("143C22") },
                "wrote the palette hex raw — the Display P3 compensation is not wired in")
        #expect(!writes.contains { $0.path == "/dev/ttys004" }, "unknown wrote to a tty")
    }
}

/// The wiring test. `DisplayP3CompensationTests` proves the transform; this proves the writer
/// actually calls it, which is a separate claim — a correct function nobody invokes ships the
/// same bug.
@Suite("OSC colour writer applies Display P3 compensation")
struct OSCColorWriterCompensationTests {
    @Test("every palette colour reaches the device compensated")
    func compensatesOnTheWire() async {
        let expected = [(TintPalette.ready, "264A30"),
                        (TintPalette.blocked, "59421B"),
                        (TintPalette.normal, "161A1E"),
                        (TintPalette.readySubtle, "1A3722"),
                        (TintPalette.readyLouder, "336646"),
                        (TintPalette.readyLoudest, "41834E")]
        #expect(expected.count == 6)
        for (colour, wire) in expected {
            let recorder = RecordingDeviceWriter()
            let writer = OSCColorWriter { path, bytes in
                Task { await recorder.record(path, bytes) }
                return true
            }
            #expect(await writer.setBackground(colour, onTTY: "/dev/ttys009"))
            try? await Task.sleep(nanoseconds: 30_000_000)
            let bytes = await recorder.writes.first?.bytes ?? ""
            #expect(bytes == "\u{1B}]1337;SetColors=bg=\(wire)\u{07}",
                    "palette #\(colour.hex) should go on the wire as #\(wire)")
        }
    }
}
