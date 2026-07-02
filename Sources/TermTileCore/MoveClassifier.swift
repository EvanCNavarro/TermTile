import CoreGraphics

/// A frame change the tiler initiated via an AX write, awaiting its echoing
/// `AXWindowMoved`/`AXWindowResized` notification. One `PendingMove` records ONE AX
/// write's intended frame — see the ledger contract on `MoveClassifier`.
public struct PendingMove: Equatable, Sendable {
    public let windowID: CGWindowID
    public let expectedFrame: CGRect
    /// Absolute wall-clock deadline (CLOCK_REALTIME seconds). The caller stamps it;
    /// classification stays pure by taking `nowEpoch` as a parameter.
    public let expiresAtEpoch: Double

    public init(windowID: CGWindowID, expectedFrame: CGRect, expiresAtEpoch: Double) {
        self.windowID = windowID
        self.expectedFrame = expectedFrame
        self.expiresAtEpoch = expiresAtEpoch
    }
}

/// Origin of an observed window frame-change. `.internal` = the tiler's own AX write
/// echoing back (must be IGNORED to avoid a feedback loop); `.external` = a user drag
/// (or any other actor) the tiler must act on.
public enum MoveOrigin: Equatable, Sendable {
    case `internal`
    case external
}

/// Distinguishes the tiler's own AX-write echoes from genuine user drags via a
/// pending-expectation ledger (Swindler's `external`-flag pattern — research
/// docs/research/macos-tiling-research.md:47-51). Pure: no clock, no AX, no state.
///
/// LEDGER CONTRACT (spike-05 §e, docs/research/spikes/05-axobserver-events.md): a single
/// tiler write of `size→pos→size` emits SEPARATE `resized` and `moved` notifications, and
/// under async write dispatch (research :41-45) the `resized` echo can carry an
/// INTERMEDIATE `(newSize, oldPos)` frame. The caller (#9/#11 TilingActor) MUST therefore
/// record ONE `PendingMove` per AX write it issues — not just the final frame — so every
/// echo matches some expectation. This classifier only asks "does the observed frame match
/// ANY non-expired pending for this window"; populating the ledger per-write is the
/// caller's responsibility.
public enum MoveClassifier {
    /// `.internal` iff some non-expired (`expiresAtEpoch >= nowEpoch`) pending move for
    /// this `windowID` has an `expectedFrame` matching `observedFrame` within `epsilon`
    /// on every component (via `FrameMath.approximatelyEqual`). Otherwise `.external`.
    public static func classify(
        windowID: CGWindowID,
        observedFrame: CGRect,
        nowEpoch: Double,
        pending: [PendingMove],
        epsilon: CGFloat
    ) -> MoveOrigin {
        for move in pending
        where move.windowID == windowID
            && move.expiresAtEpoch >= nowEpoch
            && FrameMath.approximatelyEqual(move.expectedFrame, observedFrame, epsilon: epsilon) {
            return .internal
        }
        return .external
    }
}
