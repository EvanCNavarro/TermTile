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

    /// ON-DEMAND reorder at drag END (#26) — enumerate FRESH (the dragged window now at its dropped
    /// position), reassign it to the nearest grid slot, shuffle the rest, apply. No-op if `draggedID`
    /// isn't among the current windows.
    public func reorderDropFresh(_ draggedID: CGWindowID, config: TileConfig) async {
        let windows = await system.tileableWindows()
        guard windows.contains(where: { $0.id == draggedID }) else { return }
        // AX enumerates in z-order, but `reorderCommands` maps position j → slot j, so it needs SLOT
        // order (#26 B1). The NON-dragged windows are still on their grid slots, and TileLayout is
        // column-major (`frame[k]` = column k/2, row k%2, top-first) → their frames sort into slot
        // order by (minX, minY) (same-column windows share an exact x → minY breaks the tie). The
        // dragged window sorts arbitrarily but is removed-by-id + re-inserted at its nearest slot, so
        // only the others' relative order matters — which the sort fixes.
        let slotOrdered = windows.sorted {
            ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY)
        }
        let (_, commands) = TileEngine.reorderCommands(
            windows: slotOrdered, draggedID: draggedID, config: config, epsilon: epsilon)
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
