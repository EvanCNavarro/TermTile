import Foundation
import TermTileCore

/// Which sessions have DECLARED that they are running a long autonomous loop (#51).
///
/// A port, because loop state is the one thing in this feature that cannot be read off the screen.
/// Measured 2026-09-23 on a live `/loop /goal` session: the `/loop` command and every cycle marker
/// sat 100+ lines back and were historical, the tool's own session registry reports only
/// `busy`/`idle`/`shell`, and during a dormant stretch between cycles the pane is indistinguishable
/// from one that has finished. So the session declares it, and TermTile reads the declaration.
public protocol LoopFlagReading: Sendable {
    /// The ttys currently declaring a loop, as `/dev/ttysNNN`.
    func loopingTTYs() async -> Set<String>
}

/// A reader that never reports a loop. The DEFAULT, so nothing acquires filesystem behaviour by
/// accident — the composition root injects the real one explicitly (ADR-0001).
public struct NoLoopFlags: LoopFlagReading {
    public init() {}
    public func loopingTTYs() async -> Set<String> { [] }
}

/// The production adapter: one file per looping session, named for its tty, containing its pid.
///
/// `~/.claude/termtile-loop/ttys000` holding `12345`.
///
/// **PID-GUARDED, and that is the whole safety story.** A flag left behind by a loop that was
/// killed would strand a window purple forever — the `waiting-on-a-person` failure shape, a
/// durable marker outliving the state it describes (ADR-0006 finding 10). A flag whose pid is no
/// longer alive is ignored AND deleted, so the failure self-heals on the next pass.
///
/// This does reintroduce an out-of-tree flag directory of the kind EvanCNavarro/TermTile#27 just
/// removed, and that deserves naming rather than glossing: the old flags existed because TermTile
/// could not see the screen, and they died the moment it could. This one exists because the screen
/// genuinely does not carry the answer. A signal that is underivable is a different case from one
/// that was merely inconvenient to derive.
public struct LoopFlagDirectory: LoopFlagReading {
    private let directory: URL
    private let isAlive: @Sendable (Int32) -> Bool

    /// - Parameter isAlive: injected so the pid guard is testable without spawning processes.
    public init(directory: URL? = nil,
                isAlive: @escaping @Sendable (Int32) -> Bool = LoopFlagDirectory.processIsAlive) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/termtile-loop", isDirectory: true)
        self.isAlive = isAlive
    }

    public func loopingTTYs() async -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var live: Set<String> = []
        for name in names {
            // The filename IS the tty, and it is validated the same way the OSC writer validates
            // before opening a device: a name that is not `ttysNNN` is not ours and is left alone.
            guard OSCSequence.isWritableTerminalDevice("/dev/" + name) else { continue }
            let file = directory.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: file, encoding: .utf8),
                  let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }
            if isAlive(pid) {
                live.insert("/dev/" + name)
            } else {
                // Reap it here rather than leaving it to rot: a stale flag is the one way this
                // mechanism can lie, so the lie is removed the first time it is noticed.
                try? FileManager.default.removeItem(at: file)
            }
        }
        return live
    }

    /// Signal 0 tests for existence without delivering anything.
    public static let processIsAlive: @Sendable (Int32) -> Bool = { pid in
        kill(pid, 0) == 0 || errno == EPERM
    }
}
