import CoreGraphics

/// An instruction to write a window to a target frame — the reducer's output type and the
/// unit the imperative shell's AX adapter (#10) applies. Emitting a command implies the
/// tiler will observe an echoing `AXWindowMoved`/`AXWindowResized`; the caller records a
/// matching `PendingMove` (see `WindowState.recording(commands:expiresAtEpoch:)`) so that
/// echo classifies `.internal` (ADR-0001 rule 3, feedback-loop safety).
///
/// #9 emits none of these — command emission is #10 (retile) / #11 (drag-reorder) reducer
/// cases. This type + `pending(expiresAtEpoch:)` land now so the ledger mechanism is proven.
public struct FrameCommand: Equatable, Sendable {
    public let windowID: CGWindowID
    public let targetFrame: CGRect

    public init(windowID: CGWindowID, targetFrame: CGRect) {
        self.windowID = windowID
        self.targetFrame = targetFrame
    }

    /// The pending-move expectation this command registers: its `targetFrame` is the frame
    /// the tiler expects to see echoed back for `windowID` before `expiresAtEpoch`.
    public func pending(expiresAtEpoch: Double) -> PendingMove {
        PendingMove(windowID: windowID, expectedFrame: targetFrame, expiresAtEpoch: expiresAtEpoch)
    }
}
