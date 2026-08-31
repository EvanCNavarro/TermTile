import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// LIVE END-TO-END proof of ADR-0006 Tier 1's read path: both adapters against the real machine,
/// joined by the real join, classified by the real classifier. The two halves passing separately
/// does not establish that they AGREE about which window is which — this does.
///
///     TT_LIVE_AX=1 swift test --filter TintingPipelineLiveTests
struct TintingPipelineLiveTests {
    static var liveEnabled: Bool { ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1" }

    @Test("AX panes join to real ttys and classify", .enabled(if: liveEnabled))
    func joinsLive() async {
        let panes = await AXSessionReader(bundleID: "com.googlecode.iterm2").visiblePanes()
        let sessions = await ProcessTTYProbe().sessions()

        // POSITIVE COUNTS FIRST on BOTH sides: if either read is empty the join below is
        // vacuously "fine" and proves nothing.
        #expect(!panes.isEmpty, "AX side read nothing")
        #expect(!sessions.isEmpty, "tty side read nothing")

        let outcomes = SessionJoin.resolve(panes: panes.map(\.snapshot), sessions: sessions)
        #expect(outcomes.count == panes.count)

        var resolved = 0
        for (pane, outcome) in zip(panes, outcomes) {
            let state = AgentStateClassifier.classify(scrollback: pane.scrollbackTail)
            switch outcome {
            case .resolved(let tty):
                resolved += 1
                // The joined session's cwd MUST match the pane's own — if it does not, the join
                // matched the wrong window and every tint from here would be wrong.
                let matched = sessions.first { $0.tty == tty }
                #expect(matched?.cwd == pane.snapshot.cwd,
                        "join mismatch: pane cwd \(pane.snapshot.cwd) resolved to \(tty)")
                print("LIVE-JOIN  badge=\(pane.snapshot.windowBadge.map(String.init) ?? "-")"
                    + "  \(pane.snapshot.cwd) -> \(tty)  state=\(state)")
            case .ambiguous(let reason):
                print("LIVE-JOIN  badge=\(pane.snapshot.windowBadge.map(String.init) ?? "-")"
                    + "  \(pane.snapshot.cwd) -> AMBIGUOUS(\(reason.rawValue))  state=\(state)")
            }
        }
        #expect(resolved > 0, "every pane came back ambiguous — the join is not working live")
    }
}
