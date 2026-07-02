import CoreGraphics

/// The pure retile POLICY (ADR-0001 rule 1 — the functional core). Maps the tracked windows,
/// in slot order, onto `TileLayout`'s column-of-2 grid and returns the `FrameCommand`s needed
/// to bring them there. This is both the toggle-on path (retile everything) and the core the
/// reducer's create/destroy cases reuse. No clock, no AX, no state — testable with plain values.
///
/// It records NO pending expectations: the ledger is populated by the imperative shell's actor
/// when it ISSUES the AX writes (one pending per write — `MoveClassifier` ledger contract),
/// since only the actor knows the size→pos→size decomposition and the write-time clock.
public enum TileEngine {
    /// Commands to tile `windows` into `config.visibleFrame`. Empty when disabled or when there
    /// are no windows. A command is emitted for slot `k` ONLY when `windows[k]` is not already
    /// within `epsilon` of its target frame — idempotence, so a retile over an already-on-grid
    /// set (a phantom event, a redundant toggle) issues zero writes and causes no feedback churn.
    public static func retileCommands(
        windows: [TrackedWindow],
        config: TileConfig,
        epsilon: CGFloat
    ) -> [FrameCommand] {
        guard config.isEnabled, !windows.isEmpty else { return [] }
        let frames = TileLayout.frames(count: windows.count, visibleFrame: config.visibleFrame, gap: config.gap)
        return zip(windows, frames).compactMap { window, target in
            FrameMath.approximatelyEqual(window.frame, target, epsilon: epsilon)
                ? nil
                : FrameCommand(windowID: window.id, targetFrame: target)
        }
    }

    /// Drag snap-reorder (spec-draft:25-28, ADR-0001 rule 1). On drag END the shell passes the
    /// dragged window's id; its CURRENT cached frame — kept fresh by the mid-drag `.moved` echoes
    /// the reducer folds (`WindowStateReducer` updates the cached frame for external moves too) —
    /// is the drop point. Reassigns the dragged window to the slot whose CENTER is nearest the
    /// drop-point center, shuffles the rest to fill (stable list remove+insert preserves their
    /// relative order), and returns the new slot order plus the `retileCommands` to snap everyone
    /// home. Pure: no clock, no AX, no pending (the actor records pendings per AX write — #18).
    ///
    /// No-op — returns `windows` unchanged and `[]` — when disabled or when `draggedID` isn't
    /// tracked (empty `windows` is subsumed: no id can be present). This leading guard runs BEFORE
    /// any geometry, so an empty/untracked call never argmins over an empty slot array. Distance
    /// ties resolve to the lowest slot index (stable argmin, strict `<`). N=1 is not special: the
    /// identity reorder still lets `retileCommands` snap a dragged-away lone window back to its slot.
    ///
    /// Drag-END DETECTION (global mouse-up, spike-06) is the imperative shell's job (#12), not
    /// Core's — this function is the pure policy invoked once the shell has decided the drag ended.
    public static func reorderCommands(
        windows: [TrackedWindow],
        draggedID: CGWindowID,
        config: TileConfig,
        epsilon: CGFloat
    ) -> (windows: [TrackedWindow], commands: [FrameCommand]) {
        guard config.isEnabled,
              let draggedIndex = windows.firstIndex(where: { $0.id == draggedID }) else {
            return (windows, [])
        }
        let dragged = windows[draggedIndex]
        let dropCenter = CGPoint(x: dragged.frame.midX, y: dragged.frame.midY)
        let slots = TileLayout.frames(count: windows.count, visibleFrame: config.visibleFrame, gap: config.gap)

        var targetSlot = 0
        var bestDistanceSquared = CGFloat.greatestFiniteMagnitude
        for (k, slot) in slots.enumerated() {
            let dx = slot.midX - dropCenter.x
            let dy = slot.midY - dropCenter.y
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                targetSlot = k
            }
        }

        var newOrder = windows
        newOrder.remove(at: draggedIndex)
        newOrder.insert(dragged, at: targetSlot)
        return (newOrder, retileCommands(windows: newOrder, config: config, epsilon: epsilon))
    }
}
