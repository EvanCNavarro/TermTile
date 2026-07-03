import CoreGraphics
import Foundation
import TermTileCore

/// The single actor that owns the window system (ADR-0001 rule 4). It holds the `WindowSystem`
/// adapter, a cached `WindowState` snapshot (reads never block on AX), and serializes all
/// writes. Observed events are folded through the PURE `WindowStateReducer.reduce`; emitted
/// `[FrameCommand]`s are applied via the port, each recording ONE `PendingMove` per AX WRITE so
/// the tiler's own write echoes classify `.internal` and never trigger a re-tile (rule 3).
///
/// The wall clock lives here (Kit is the imperative shell): `Date().timeIntervalSince1970`
/// feeds `reduce`'s `nowEpoch` and stamps pending deadlines; Core stays pure by taking them as
/// parameters. `ttlSeconds` is the pending-expiry window (~1s, spec-draft:5) — distinct from
/// #19's AX *messaging* timeout, which is the adapter's concern.
public actor TilingActor {
    private let system: any WindowSystem
    private var state: WindowState
    private var config: TileConfig
    private let epsilon: CGFloat
    private let ttlSeconds: Double

    public init(system: any WindowSystem, config: TileConfig = .disabled,
                epsilon: CGFloat = 2, ttlSeconds: Double = 1.0) {
        self.system = system
        self.state = WindowState()
        self.config = config
        self.epsilon = epsilon
        self.ttlSeconds = ttlSeconds
    }

    /// The cached window snapshot — an instant read that never touches AX.
    public var snapshot: WindowState { state }

    /// The tracked window whose cached frame contains `point`, or `nil` if none does. Used by the
    /// drag-monitor (#14b) to resolve the dragged id at mouse-DOWN — while the windows are still on
    /// their grid slots (NON-overlapping), so at most one frame contains the cursor and the answer
    /// is unambiguous (skeptic B1: resolving at mouse-UP would be ambiguous, the dragged window
    /// overlapping its drop target). Insertion order is not z-order, so this is only sound on the
    /// non-overlapping tiled snapshot; first containing match wins.
    public func windowID(at point: CGPoint) -> CGWindowID? {
        state.windows.first { $0.frame.contains(point) }?.id
    }

    /// Toggle-on / authoritative reset: adopt `config`, re-enumerate the target app's tileable
    /// windows as the source of truth, and tile them all onto the grid.
    public func activate(config: TileConfig) async {
        self.config = config
        let windows = await system.tileableWindows()
        state = WindowState(windows: windows)
        await apply(TileEngine.retileCommands(windows: windows, config: config, epsilon: epsilon))
    }

    /// Fold one observed event through the pure reducer, then apply any emitted commands. A
    /// window-set change while enabled emits retile commands; our own write echoes classify
    /// `.internal`, drain the ledger, and emit nothing.
    public func handle(_ event: WindowEvent) async {
        let (next, commands) = WindowStateReducer.reduce(
            state, event, nowEpoch: Date().timeIntervalSince1970, epsilon: epsilon, config: config)
        state = next
        await apply(commands)
    }

    /// Drag snap-reorder at drag END (spec-draft:25-28). The imperative shell — a global
    /// mouse-up CGEventTap (spike-06), wired in #12 — passes the dragged window's id when a drag
    /// finishes. Its cached frame (kept fresh by the mid-drag `.moved` echoes `handle` folds) is
    /// the drop point: the pure `TileEngine.reorderCommands` reassigns it to the nearest slot,
    /// shuffles the rest, and returns the snap commands, which `apply` issues while recording one
    /// pending per AX write so the snap's own echoes classify `.internal` and never re-tile.
    /// No-op when disabled or the id isn't tracked.
    public func handleDragEnd(_ windowID: CGWindowID) async {
        let (newOrder, commands) = TileEngine.reorderCommands(
            windows: state.windows, draggedID: windowID, config: config, epsilon: epsilon)
        state.windows = newOrder
        await apply(commands)
    }

    /// Consume the port's event stream (ADR rule 4 — the AXObserver is bridged ONCE at the
    /// adapter into this stream). Returns when the stream finishes.
    public func run() async {
        for await event in system.events() {
            await handle(event)
        }
    }

    /// Apply commands via the port, recording the expectation ledger. For each command the actor
    /// records ONE `PendingMove` per AX write it is about to cause — the size→pos→size trio
    /// `[(target.size, cachedOrigin), target, target]` — before issuing the write, so every
    /// echo (including the intermediate `(newSize, oldPos)` resize and the redundant final
    /// resize) matches a distinct pending. Unmatched leftovers self-heal via the reducer's
    /// TTL-GC. The pre-write origin comes from the cached snapshot (only the actor holds it).
    private func apply(_ commands: [FrameCommand]) async {
        for command in commands {
            let cachedOrigin = state.windows.first { $0.id == command.windowID }?.frame.origin
                ?? command.targetFrame.origin
            let target = command.targetFrame
            let perWrite = [
                CGRect(origin: cachedOrigin, size: target.size),   // size1: new size at old origin
                target,                                             // pos:   old size cleared to target
                target,                                             // size2: redundant confirm write
            ]
            let expiry = Date().timeIntervalSince1970 + ttlSeconds
            state = state.recording(
                commands: perWrite.map { FrameCommand(windowID: command.windowID, targetFrame: $0) },
                expiresAtEpoch: expiry)
            _ = await system.writeFrame(command.windowID, to: target)
        }
    }
}
