@testable import TermTileKit
import TermTileCore

/// Deterministic in-memory `SessionReading` fake (ADR-0001 rule 2, test adapter). An `actor` so
/// it satisfies the `Sendable` port. Live-AX behaviour belongs to `AXSessionReader` and is proven
/// by the opt-in live test; this fake exercises everything downstream with plain values.
actor InMemorySessionReader: SessionReading {
    private var seeded: [ObservedPane]
    /// How many times `visiblePanes()` was called — lets a test prove the coordinator polls
    /// rather than caching a first read forever.
    private(set) var readCount = 0

    init(panes: [ObservedPane] = []) {
        self.seeded = panes
    }

    func visiblePanes() -> [ObservedPane] {
        readCount += 1
        return seeded
    }

    /// Replace the observed panes — simulates windows opening, closing, or changing state.
    func reseed(_ panes: [ObservedPane]) { seeded = panes }
}
