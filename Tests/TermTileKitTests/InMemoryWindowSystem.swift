import CoreGraphics
@testable import TermTileKit
import TermTileCore

/// Deterministic in-memory `WindowSystem` fake (ADR-0001 rule 2, test adapter). An `actor` so it
/// satisfies the `Sendable` port and records writes under isolation. Live-AX behaviour is #19's
/// adapter; this fake exercises the actor's on-demand tiling/reorder with plain values.
actor InMemoryWindowSystem: WindowSystem {
    /// The windows `tileableWindows()` returns (enumeration order — NOT necessarily slot order).
    private var seeded: [TrackedWindow]
    /// Every `writeFrame` call, in order — the actor's applied-command trail.
    private(set) var recordedWrites: [(id: CGWindowID, target: CGRect)] = []

    init(windows: [TrackedWindow] = []) {
        self.seeded = windows
    }

    func tileableWindows() -> [TrackedWindow] { seeded }

    func writeFrame(_ id: CGWindowID, to target: CGRect) -> Bool {
        recordedWrites.append((id, target))
        return true
    }

    /// Replace the enumerated window set — simulates the target app's windows changing (used to
    /// prove `activate()`/`reorderDropFresh` re-enumerate fresh as the source of truth).
    func reseed(_ windows: [TrackedWindow]) { seeded = windows }

    /// Drop the recorded-write trail so a later phase's writes can be asserted in isolation.
    func clearWrites() { recordedWrites = [] }
}
