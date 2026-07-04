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

    /// Drag snap-reorder (#11/#27, ADR-0001 rule 1). Given a FRESH window enumerate (the dragged
    /// window at its DROP position, the others still on their grid slots) + the chosen `strategy`,
    /// returns the new column-major slot order + the `retileCommands` to snap everyone there. Pure.
    ///
    /// SHARED MODEL (skeptic-mandated, #27): drop the dragged window by id, assign each remaining
    /// window to its nearest slot (on a tiled grid this is exact + injective) → the `targetSlot`'s
    /// occupant and the `vacatedSlot` (the one slot no window claims = the dragged window's origin)
    /// both fall out. NO-OP guard: dropping nearest one's own origin (`targetSlot == vacatedSlot`) is
    /// the identity. All four strategies are pure permutations built on this (see `ReorderStrategy`).
    ///
    /// Precondition: reorder is only well-defined from a TILED grid. If the windows aren't tiled
    /// (the user enabled reorder without a Rearrange → overlapping), nearest-slot can't infer origins;
    /// it degrades to a plain retile (snap everyone to the grid, no meaningful reorder) — never a crash.
    ///
    /// No-op — returns `windows` unchanged, `[]` — when disabled or `draggedID` isn't tracked. Distance
    /// ties resolve to the lowest slot index (stable argmin). Drag-END detection is the shell's job.
    public static func reorderCommands(
        windows: [TrackedWindow],
        draggedID: CGWindowID,
        config: TileConfig,
        epsilon: CGFloat,
        strategy: ReorderStrategy
    ) -> (windows: [TrackedWindow], commands: [FrameCommand]) {
        guard config.isEnabled, let dragged = windows.first(where: { $0.id == draggedID }) else {
            return (windows, [])
        }
        let n = windows.count
        let slots = TileLayout.frames(count: n, visibleFrame: config.visibleFrame, gap: config.gap)

        // Shared model: nearest-slot assignment of the NON-dragged windows.
        var occupant = [TrackedWindow?](repeating: nil, count: n)
        for window in windows where window.id != draggedID {
            occupant[nearestSlot(to: window.frame, in: slots)] = window
        }
        // Untiled fallback: not exactly one empty slot → can't infer origins → plain grid snap.
        let emptySlots = occupant.enumerated().filter { $0.element == nil }
        guard emptySlots.count == 1, let vacatedSlot = emptySlots.first?.offset else {
            let sorted = windows.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            return (sorted, retileCommands(windows: sorted, config: config, epsilon: epsilon))
        }
        let targetSlot = nearestSlot(to: dragged.frame, in: slots)

        let ordered: [TrackedWindow]
        if targetSlot == vacatedSlot {
            var assignment = occupant                      // dropped nearest own origin → identity
            assignment[vacatedSlot] = dragged
            ordered = assignment.map { $0! }
        } else {
            let effective = (strategy == .adaptive)
                ? adaptiveStrategy(dragged: dragged, origin: slots[vacatedSlot]) : strategy
            ordered = permute(effective, occupant: occupant, dragged: dragged,
                              indices: (targetSlot, vacatedSlot), slots: slots)
        }
        return (ordered, retileCommands(windows: ordered, config: config, epsilon: epsilon))
    }

    /// The slot index whose center is nearest `frame`'s center (stable argmin, lowest index on ties).
    private static func nearestSlot(to frame: CGRect, in slots: [CGRect]) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (k, slot) in slots.enumerated() {
            let dx = slot.midX - frame.midX, dy = slot.midY - frame.midY
            let distance = dx * dx + dy * dy
            if distance < bestDistance { bestDistance = distance; best = k }
        }
        return best
    }

    /// Adaptive: a mostly-horizontal drag (|dx| ≥ |dy| from the origin slot) → rowShift; else column.
    private static func adaptiveStrategy(dragged: TrackedWindow, origin: CGRect) -> ReorderStrategy {
        abs(dragged.frame.midX - origin.midX) >= abs(dragged.frame.midY - origin.midY)
            ? .rowShift : .columnShift
    }

    /// The new column-major slot assignment for a concrete (non-adaptive) strategy. `occupant[k]` is
    /// the window on slot k (nil only at `vacatedSlot`); returns `[window per slot 0..<n]`.
    private static func permute(
        _ strategy: ReorderStrategy, occupant: [TrackedWindow?], dragged: TrackedWindow,
        indices: (target: Int, vacated: Int), slots: [CGRect]
    ) -> [TrackedWindow] {
        let n = occupant.count
        let (targetSlot, vacatedSlot) = indices
        switch strategy {
        case .swap:
            var a = occupant
            a[vacatedSlot] = a[targetSlot]                 // target's occupant → the vacated slot
            a[targetSlot] = dragged
            return a.map { $0! }
        case .columnShift:
            var seq = (0..<n).map { $0 == vacatedSlot ? dragged : occupant[$0]! }   // column-major
            seq.remove(at: vacatedSlot)
            seq.insert(dragged, at: targetSlot)
            return seq                                     // seq[k] → slot k
        case .rowShift:
            let rowMajor = (0..<n).sorted { (slots[$0].minY, slots[$0].minX) < (slots[$1].minY, slots[$1].minX) }
            var seq = rowMajor.map { $0 == vacatedSlot ? dragged : occupant[$0]! }
            seq.remove(at: rowMajor.firstIndex(of: vacatedSlot)!)
            seq.insert(dragged, at: rowMajor.firstIndex(of: targetSlot)!)
            var a = [TrackedWindow?](repeating: nil, count: n)
            for (position, slot) in rowMajor.enumerated() { a[slot] = seq[position] }   // scatter back
            return a.map { $0! }
        case .adaptive:
            return occupant.map { $0 ?? dragged }          // unreachable (resolved before permute)
        }
    }
}
