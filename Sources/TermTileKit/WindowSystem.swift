import CoreGraphics
import TermTileCore

/// The single window-system port (ADR-0001 rule 2). ALL window access — enumeration, frame
/// reads/writes, and the observed-event stream — flows through this one seam. The production
/// adapter (#19) is AX (imports ApplicationServices — the only control surface, with the
/// size→position→size + `AXEnhancedUserInterface`-off workarounds); the test adapter is an
/// in-memory fake. The vocabulary is `CGWindowID` / `CGRect` / `TrackedWindow` / `WindowEvent`
/// only, so this file imports no ApplicationServices — id resolution (incl. the destroy
/// `-25201` element→id map) is the adapter's private concern, delivered here already resolved.
///
/// The read/enumerate/write calls are `async`: a Swift 6 `actor` adapter (or the fake) can
/// only witness a `Sendable` protocol requirement when it is `async` (a synchronous isolated
/// method cannot satisfy a nonisolated requirement). `events()` returns the stream handle
/// synchronously; the actor consumes it with `for await` (ADR rule 4 — bridged ONCE at the
/// adapter).
public protocol WindowSystem: Sendable {
    /// Currently tileable windows of the target app, in enumeration (slot) order. The adapter
    /// applies `WindowFiltering` (standard, unminimized, unfullscreened); the fake returns its
    /// seed.
    func tileableWindows() async -> [TrackedWindow]

    /// Move + resize the window to `target`. The adapter performs the size→position→size write
    /// (with `AXEnhancedUserInterface` disabled) — that decomposition is the adapter's job.
    /// Returns `true` on success. The CALLER (`TilingActor`) predicts and records the per-write
    /// pending expectations from its cached snapshot (ledger contract, `MoveClassifier`), since
    /// only it holds the write-time clock and the pre-write origin.
    func writeFrame(_ id: CGWindowID, to target: CGRect) async -> Bool

    /// The observed window-event stream (ADR rule 4). The adapter bridges its per-pid
    /// AXObserver callbacks into this stream ONCE; no AX callbacks live anywhere else.
    func events() -> AsyncStream<WindowEvent>
}
