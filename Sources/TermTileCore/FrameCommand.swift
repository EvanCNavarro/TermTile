import CoreGraphics

/// An instruction to write a window to a target frame — the pure tiling engine's output type and
/// the unit the imperative shell's AX adapter (#10) applies. `TileEngine.retileCommands` (Rearrange)
/// and `reorderCommands` (drag-reorder) emit these; `TilingActor.apply` writes each one.
public struct FrameCommand: Equatable, Sendable {
    public let windowID: CGWindowID
    public let targetFrame: CGRect

    public init(windowID: CGWindowID, targetFrame: CGRect) {
        self.windowID = windowID
        self.targetFrame = targetFrame
    }
}
