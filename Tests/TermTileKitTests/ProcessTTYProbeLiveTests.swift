import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// LIVE PROOF of the real probe against this machine's actual process table.
///
/// Shares the `TT_LIVE_AX=1` switch with `AXSessionReaderLiveTests` — one flag for "the live
/// local surface", since neither works on a CI runner (no iTerm, no agent sessions):
///
///     TT_LIVE_AX=1 swift test --filter ProcessTTYProbeLiveTests
struct ProcessTTYProbeLiveTests {
    static var liveEnabled: Bool { ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1" }

    @Test("reads real agent sessions: tty, window/tab/pane and cwd", .enabled(if: liveEnabled))
    func readsLiveSessions() async {
        let sessions = await ProcessTTYProbe().sessions()

        // POSITIVE COUNT FIRST — an empty read would run zero assertions below and pass.
        #expect(!sessions.isEmpty, "no agent sessions found — is an agent running in iTerm2?")

        var ttys = Set<String>()
        for session in sessions {
            #expect(session.tty.hasPrefix("/dev/ttys"), "malformed tty \(session.tty)")
            #expect(session.windowIndex >= 0)
            #expect(session.tabIndex >= 0)
            #expect(session.paneIndex >= 0)
            #expect(!session.cwd.isEmpty)
            #expect(ttys.insert(session.tty).inserted, "duplicate tty \(session.tty)")
            print("LIVE-TTY  \(session.tty)  w\(session.windowIndex)"
                + "t\(session.tabIndex)p\(session.paneIndex)  cwd=\(session.cwd)")
        }
    }
}
