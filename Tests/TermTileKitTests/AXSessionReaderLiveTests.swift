import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// LIVE PROOF of the real AX adapter (.engine/MEMORY.md: this project's live surface is AX
/// against ANOTHER app's real windows, so a passing unit test is not evidence the adapter works).
///
/// Opt-in via `TT_LIVE_AX=1` because it needs a running iTerm2 AND an Accessibility grant for
/// whatever process hosts the test — neither exists on a CI runner. Gated rather than deleted so
/// the proof is repeatable by anyone, not a screenshot in a commit message:
///
///     TT_LIVE_AX=1 swift test --filter AXSessionReaderLiveTests
struct AXSessionReaderLiveTests {
    static var liveEnabled: Bool { ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1" }

    @Test("reads real iTerm2 panes: badge, cwd and a bounded tail",
          .enabled(if: liveEnabled))
    func readsLivePanes() async {
        let reader = AXSessionReader(bundleID: "com.googlecode.iterm2")
        let panes = await reader.visiblePanes()

        // POSITIVE COUNT FIRST: an empty read would run zero assertions below and "pass",
        // which is the failure mode this whole suite exists to avoid.
        #expect(!panes.isEmpty, "no panes read — is iTerm2 running and Accessibility granted?")

        for pane in panes {
            #expect(!pane.snapshot.cwd.isEmpty, "a pane was returned with an empty cwd")
            #expect(pane.scrollbackTail.count <= AgentStateClassifier.tailWindow,
                    "tail \(pane.scrollbackTail.count) chars exceeded the window — ranged read regressed")
            if let badge = pane.snapshot.windowBadge {
                #expect(ITermBadge.validRange.contains(badge), "badge \(badge) out of range")
            }
        }

        #expect(panes.contains { $0.snapshot.windowBadge != nil },
                "no pane carried a badge — the join's primary key is not being read")

        for pane in panes {
            let state = AgentStateClassifier.classify(scrollback: pane.scrollbackTail)
            let badge = pane.snapshot.windowBadge.map(String.init) ?? "-"
            print("LIVE  badge=\(badge)  cwd=\(pane.snapshot.cwd)  "
                + "tail=\(pane.scrollbackTail.count)ch  state=\(state)")
        }
    }
}
