import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// LIVE END-TO-END through the REAL writer — the last leg no other test covers.
///
/// `TintingCoordinatorLiveTests` proves the DECISIONS on live data but swaps in a recording writer.
/// This drives the identical stack the app composes, including `OSCColorWriter`, so the only thing
/// between this and the shipped app is the composition root itself.
///
/// Uses the LOUDEST ready shade deliberately: the out-of-tree poller writes the STANDARD shade, so
/// a session showing loudest could only have been painted by this code.
///
///     TT_LIVE_AX=1 TT_LIVE_WRITE=1 swift test --filter TintingEndToEndLiveTests
struct TintingEndToEndLiveTests {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1"
            && ProcessInfo.processInfo.environment["TT_LIVE_WRITE"] == "1"
    }

    @Test("the real stack paints real sessions", .enabled(if: enabled))
    func paintsLive() async throws {
        let coordinator = TintingCoordinator(
            reader: AXSessionReader(bundleID: "com.googlecode.iterm2"),
            probe: ProcessTTYProbe(),
            writer: OSCColorWriter(),
            readyColor: ReadyIntensity.loudest.color)

        let first = await coordinator.pass()
        #expect(!first.isEmpty, "no panes — is iTerm2 running with agent sessions?")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let second = await coordinator.pass()

        for d in second {
            print("E2E  \(d.cwd) -> \(d.tty ?? "-")  \(d.state)  wrote=\(d.wrote)")
        }
        let painted = second.filter(\.wrote)
        #expect(!painted.isEmpty, "the real writer painted nothing at all")
    }
}
