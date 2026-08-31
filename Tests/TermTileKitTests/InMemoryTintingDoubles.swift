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
