import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// LIVE PROOF of the coordinator's decisions against the real machine.
///
/// The reader and probe are the REAL adapters; only the WRITER is a recording double. That is a
/// deliberate split, not a shortcut: the write leg was live-proven separately (real OSC write to a
/// real tty, AppleScript readback), and repainting six of someone's terminals to re-prove it would
/// be a visible side effect bought for nothing. What this test proves is the part nothing else
/// can — that the STATEFUL delta works on live data, which needs two passes separated in time.
///
///     TT_LIVE_AX=1 swift test --filter TintingCoordinatorLiveTests
struct TintingCoordinatorLiveTests {
    static var liveEnabled: Bool { ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1" }

    @Test("two real passes: first has no delta, second classifies", .enabled(if: liveEnabled))
    func twoLivePasses() async throws {
        let tinter = RecordingTinter()
        let coordinator = TintingCoordinator(
            reader: AXSessionReader(bundleID: "com.googlecode.iterm2"),
            probe: ProcessTTYProbe(),
            writer: tinter)

        let first = await coordinator.pass()
        #expect(!first.isEmpty, "no panes read — is iTerm2 running with agent sessions?")
        // FIRST PASS HAS NO BASELINE. Every resolved pane must be unknown-or-blocked; a `.ready`
        // here would mean stillness was assumed rather than measured (ADR-0006 finding 9).
        for d in first where d.tty != nil {
            #expect(d.state != .ready, "\(d.cwd) reported ready on a first pass, with no delta")
            print("LIVE-PASS1  \(d.cwd) -> \(d.tty ?? "-")  \(d.state)  wrote=\(d.wrote)")
        }
        #expect(await tinter.writes.count == first.filter(\.wrote).count)

        try await Task.sleep(nanoseconds: 4_000_000_000)

        let second = await coordinator.pass()
        #expect(!second.isEmpty)
        for d in second {
            print("LIVE-PASS2  \(d.cwd) -> \(d.tty ?? "-")  \(d.state)  wrote=\(d.wrote)"
                + (d.ambiguity.map { "  ambiguity=\($0.rawValue)" } ?? ""))
        }
        // The point of the second pass: a delta now exists, so states become decidable.
        let decided = second.filter { $0.state != .unknown }
        #expect(!decided.isEmpty, "no pane became decidable on the second pass")

        // Nothing may be written for an unresolved or unknown pane, live or not.
        for d in second where d.tty == nil { #expect(!d.wrote) }
        for d in second where d.state == .unknown { #expect(!d.wrote) }
    }
}
