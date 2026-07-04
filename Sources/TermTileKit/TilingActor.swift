import CoreGraphics
import Foundation
import TermTileCore

/// The single actor that owns the window system (ADR-0001 rule 4) and serializes all AX writes.
/// TermTile is a MANUAL / ON-DEMAND tiler: it enumerates the target app's windows FRESH at each
/// action (Rearrange, or a drag), tiles/reorders them, and writes — it keeps NO cached window model
/// and watches no events. (The event-stream / reducer / observer machinery was cut once on-demand
/// drag-reorder #26 superseded it; continuous auto-retile would reintroduce it, but that's a
/// different, unshipped feature.)
public actor TilingActor {
    private let system: any WindowSystem
    private let epsilon: CGFloat

    public init(system: any WindowSystem, epsilon: CGFloat = 2) {
        self.system = system
        self.epsilon = epsilon
    }

    /// ON-DEMAND drag path (#26) — the dragged window's id, resolved by enumerating the target's
    /// windows FRESH at mouse-DOWN. `first{contains}` is unambiguous when the windows are tiled
    /// (non-overlapping) — the normal case after a Rearrange; if the user enabled drag-reorder without
    /// tiling and windows overlap, it relies on AX enumerating topmost-first (skeptic S1 — acceptable
    /// for MVP; the reorder then re-tiles everything anyway).
    public func windowID(atFresh point: CGPoint) async -> CGWindowID? {
        await system.tileableWindows().first { $0.frame.contains(point) }?.id
    }

    /// ON-DEMAND reorder at drag END (#26/#27) — enumerate FRESH (the dragged window now at its
    /// dropped position, the others on their slots) and hand the raw set to `reorderCommands`, whose
    /// shared model infers each window's slot + the vacated slot and applies `strategy`. No pre-sort
    /// (the model does the slot inference); no-op if `draggedID` isn't among the current windows.
    public func reorderDropFresh(_ draggedID: CGWindowID, config: TileConfig,
                                 strategy: ReorderStrategy) async {
        let windows = await system.tileableWindows()
        guard windows.contains(where: { $0.id == draggedID }) else { return }
        let (_, commands) = TileEngine.reorderCommands(
            windows: windows, draggedID: draggedID, config: config, epsilon: epsilon, strategy: strategy)
        await apply(commands)
    }

    /// Rearrange: re-enumerate the target app's tileable windows and tile them all onto the grid.
    public func activate(config: TileConfig) async {
        let windows = await system.tileableWindows()
        await apply(TileEngine.retileCommands(windows: windows, config: config, epsilon: epsilon))
    }

    /// Apply commands via the port — write each window to its target frame. (No expectation ledger:
    /// nothing consumes it now that the event stream is gone; the fresh enumerate is the truth.)
    private func apply(_ commands: [FrameCommand]) async {
        for command in commands {
            _ = await system.writeFrame(command.windowID, to: command.targetFrame)
        }
    }
}
