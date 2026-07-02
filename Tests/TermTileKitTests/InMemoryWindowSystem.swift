import CoreGraphics
@testable import TermTileKit
import TermTileCore

/// Deterministic in-memory `WindowSystem` fake (ADR-0001 rule 2, test adapter). An `actor` so
/// it satisfies the `Sendable` port and records writes under isolation. Simulates the observed
/// iTerm2 shape (spike 03: ids = `CGWindowID`; frames are real). Live-AX behavior is #19's
/// adapter; this fake exercises the actor's orchestration + ledger logic with plain values.
actor InMemoryWindowSystem: WindowSystem {
    /// The windows enumeration/reads return, in slot order.
    private var seeded: [TrackedWindow]
    /// Every `writeFrame` call, in order — the actor's applied-command trail.
    private(set) var recordedWrites: [(id: CGWindowID, target: CGRect)] = []

    private let stream: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation

    init(windows: [TrackedWindow] = []) {
        self.seeded = windows
        var cont: AsyncStream<WindowEvent>.Continuation!
        self.stream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func tileableWindows() -> [TrackedWindow] { seeded }

    func readFrame(_ id: CGWindowID) -> CGRect? { seeded.first { $0.id == id }?.frame }

    func writeFrame(_ id: CGWindowID, to target: CGRect) -> Bool {
        recordedWrites.append((id, target))
        return true
    }

    nonisolated func events() -> AsyncStream<WindowEvent> { stream }

    /// Inject one observed event into the stream (drives `TilingActor.run`).
    func emit(_ event: WindowEvent) { continuation.yield(event) }

    /// End the stream so a `for await` consumer (`run()`) terminates — prevents test hangs.
    func finish() { continuation.finish() }
}
