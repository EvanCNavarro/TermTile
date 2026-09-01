import Foundation
@testable import TermTileKit
import TermTileCore
import Testing

/// INVESTIGATION PROBE, not an assertion suite. Dumps what the AX reader actually sees per pane
/// and what the classifier makes of it, so a marker can be captured from a REAL prompt instead of
/// transcribed from a screenshot (ADR-0006 finding 11 / EvanCNavarro/TermTile#27).
///
/// These two suites are what reproduced EvanCNavarro/TermTile#34 — a session that merely DISPLAYS
/// `Esc to cancel` is scored blocked and would be painted amber. They are committed rather than
/// thrown away because that defect has no fix yet, and whatever fix arrives has to be checked
/// against a real screen, not a fixture.
///
///     TT_LIVE_AX=1 TT_DUMP=1 swift test --filter PaneDumpLiveTests
struct PaneDumpLiveTests {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TT_LIVE_AX"] == "1"
            && ProcessInfo.processInfo.environment["TT_DUMP"] == "1"
    }

    @Test("dump every visible pane and its classification", .enabled(if: enabled))
    func dump() async {
        let panes = await AXSessionReader(bundleID: "com.googlecode.iterm2").visiblePanes()
        #expect(!panes.isEmpty, "no panes read")
        let tailChars = Int(ProcessInfo.processInfo.environment["TT_DUMP_CHARS"] ?? "220") ?? 220
        for pane in panes {
            // MARKER verdict only. `unknown` here means "no blocked/working marker in the tail",
            // NOT the app's answer: ready is decided on the evidence path from a character-count
            // delta, so this overload can never return it. Adequate for the BLOCKED question,
            // which is purely marker-based, and misleading for anything else.
            let state = AgentStateClassifier.classify(scrollback: pane.scrollbackTail)
            let badge = pane.snapshot.windowBadge.map(String.init) ?? "-"
            print("=== badge=\(badge) cwd=\(pane.snapshot.cwd) chars=\(pane.characterCount) -> \(state.rawValue)")
            // NUL is what iTerm pads with (finding 7b); make it visible rather than invisible.
            let tail = pane.scrollbackTail.suffix(tailChars)
                .replacingOccurrences(of: "\u{0}", with: "·")
            print("    TAIL[\(tail.count)]: \(tail.replacingOccurrences(of: "\n", with: " ⏎ "))")
        }
    }
}

/// Drives the REAL coordinator — real AX reader, real tty probe — with a writer that records
/// instead of painting, so TermTile's actual per-pane verdict is observable without touching a
/// single window's colour. Two passes, because `ready` requires a baseline from a prior pass.
///
///     TT_LIVE_AX=1 TT_DUMP=1 swift test --filter CoordinatorVerdictLiveTests
struct CoordinatorVerdictLiveTests {
    actor NoOpWriter: SessionTinting {
        private(set) var asked: [(TintColor, String)] = []
        func setBackground(_ color: TintColor, onTTY tty: String) async -> Bool {
            asked.append((color, tty)); return true
        }
    }

    @Test("what the real coordinator decides, painting nothing", .enabled(if: PaneDumpLiveTests.enabled))
    func verdicts() async {
        let writer = NoOpWriter()
        let coordinator = TintingCoordinator(reader: AXSessionReader(bundleID: "com.googlecode.iterm2"),
                                             probe: ProcessTTYProbe(),
                                             writer: writer)
        _ = await coordinator.pass()                       // seeds baselines
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let decisions = await coordinator.pass()
        #expect(!decisions.isEmpty, "the coordinator saw no panes at all")
        for d in decisions {
            print("VERDICT \(d.state.rawValue)\twrote=\(d.wrote)\ttty=\(d.tty ?? "-")"
                  + "\tbaseline=\(d.hadBaseline)\tambiguity=\(d.ambiguity.map(String.init(describing:)) ?? "-")"
                  + "\tcwd=\(d.cwd)")
        }
        let asked = await writer.asked
        print("WOULD-PAINT \(asked.count): " + asked.map { "\($0.1)=#\($0.0.hex)" }.joined(separator: " "))
    }
}
