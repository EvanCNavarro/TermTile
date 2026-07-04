import CoreGraphics

/// A window the tiler acts on: its CGWindowID and frame. When the tiling policy reads a fresh
/// enumeration, column-major (minX, minY) order maps to `TileLayout` slots.
public struct TrackedWindow: Equatable, Sendable {
    public let id: CGWindowID
    public var frame: CGRect

    public init(id: CGWindowID, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}
