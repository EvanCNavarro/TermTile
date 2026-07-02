import CoreGraphics

/// The pure window-state transition (ADR-0001 rules 3-4, Core half). Folds one observed
/// `WindowEvent` into the cached `WindowState`, using the expectation ledger to classify
/// echoes of the tiler's own AX writes (`.internal`) vs genuine external moves. Pure: the
/// clock (`nowEpoch`) and match tolerance (`epsilon`) are parameters — no AX, no state.
///
/// #9 emits NO `FrameCommand`s for any event: the tiling/reorder POLICY (retile on
/// create/destroy, drag snap-reorder) is added as reducer cases by #10/#11. This beat lands
/// the state bookkeeping + ledger classification the policy builds on.
public enum WindowStateReducer {
    /// - Returns: the next state and the commands to apply (always empty in #9).
    ///
    /// Behavior per kind (expired pendings are GC'd first on every step so the ledger stays
    /// bounded — `MoveClassifier` also independently declines expired entries):
    /// - `.created`: append the window if new, else update its frame in place. nil frame → no-op.
    /// - `.destroyed`: remove the window by id (no-op if unknown — spike-05 ~5s undo-close
    ///   anomaly emits destroys for never-tracked elements) and drop its ledger entries.
    /// - `.moved`/`.resized`: classify the observed frame; update the cached frame only if the
    ///   window is tracked (no phantom window for an unknown id). If `.internal`, consume the
    ///   ONE pending whose `expectedFrame` matches within `epsilon` (not merely the first for
    ///   the window — a single write can leave several pendings for one id). nil frame → no-op.
    public static func reduce(
        _ state: WindowState,
        _ event: WindowEvent,
        nowEpoch: Double,
        epsilon: CGFloat
    ) -> (WindowState, [FrameCommand]) {
        var next = state
        next.pending.removeAll { $0.expiresAtEpoch < nowEpoch }

        switch event.kind {
        case .created:
            guard let frame = event.frame else { break }
            if let i = next.windows.firstIndex(where: { $0.id == event.windowID }) {
                next.windows[i].frame = frame
            } else {
                next.windows.append(TrackedWindow(id: event.windowID, frame: frame))
            }

        case .destroyed:
            next.windows.removeAll { $0.id == event.windowID }
            next.pending.removeAll { $0.windowID == event.windowID }

        case .moved, .resized:
            guard let frame = event.frame else { break }
            let origin = MoveClassifier.classify(
                windowID: event.windowID,
                observedFrame: frame,
                nowEpoch: nowEpoch,
                pending: next.pending,
                epsilon: epsilon
            )
            if let i = next.windows.firstIndex(where: { $0.id == event.windowID }) {
                next.windows[i].frame = frame
            }
            if origin == .internal,
               let j = next.pending.firstIndex(where: {
                   $0.windowID == event.windowID
                       && FrameMath.approximatelyEqual($0.expectedFrame, frame, epsilon: epsilon)
               }) {
                next.pending.remove(at: j)
            }
        }

        return (next, [])
    }
}
