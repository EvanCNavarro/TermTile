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
        // The palette hex goes out UNCONVERTED under an explicit `rgb:` space. Measured: that
        // renders exactly #143C22, identical to what the AppleScript path produces for the same
        // hex, because `rgb:` names the same device space AppleScript uses (#29).
        #expect(writes.first?.bytes == "\u{1B}]1337;SetColors=bg=rgb:143C22\u{07}")
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
        #expect(writes.contains { $0.bytes.contains("rgb:143C22") })
        #expect(writes.contains { $0.bytes.contains("rgb:4A320F") })
        #expect(writes.contains { $0.bytes.contains("rgb:111417") })
        #expect(!writes.contains { $0.bytes.contains("bg=143C22") },
                "sent a bare hex — iTerm would read it as Display P3 and render the wrong colour")
        #expect(!writes.contains { $0.path == "/dev/ttys004" }, "unknown wrote to a tty")
    }
}
