@testable import TermTileKit
import TermTileCore

/// Deterministic `TTYProbing` fake.
actor InMemoryTTYProbe: TTYProbing {
    private var seeded: [TTYSessionSnapshot]
    init(sessions: [TTYSessionSnapshot] = []) { self.seeded = sessions }
    func sessions() -> [TTYSessionSnapshot] { seeded }
    func reseed(_ sessions: [TTYSessionSnapshot]) { seeded = sessions }
}

/// Recording `SessionTinting` fake — the suite must never write to a real terminal.
actor RecordingTinter: SessionTinting {
    private(set) var writes: [(tty: String, hex: String)] = []
    @discardableResult
    func setBackground(_ color: TintColor, onTTY tty: String) -> Bool {
        writes.append((tty, color.hex))
        return true
    }
    func clear() { writes = [] }
    var writtenTTYs: [String] { writes.map(\.tty) }
    var writtenHexes: [String] { writes.map(\.hex) }
}

/// A reader whose `visiblePanes()` takes long enough that a pass can be cancelled MID-FLIGHT.
///
/// Exists for EvanCNavarro/TermTile#20: the shutdown race only appears while a pass is in progress,
/// so a fake that returns instantly can never expose it. `Task.sleep` throwing on cancellation is
/// swallowed deliberately — the real `AXSessionReader` does not abandon a half-finished AX read
/// either, and the point is to model a pass that RUNS ON past the cancel.
actor SlowSessionReader: SessionReading {
    private let delay: Duration
    private let panes: [ObservedPane]
    /// Incremented on ENTRY, so a test can tell a pass has begun without waiting for it to end.
    private(set) var entered = 0

    init(panes: [ObservedPane], delay: Duration = .milliseconds(200)) {
        self.panes = panes
        self.delay = delay
    }

    func visiblePanes() async -> [ObservedPane] {
        entered += 1
        try? await Task.sleep(for: delay)
        return panes
    }
}
