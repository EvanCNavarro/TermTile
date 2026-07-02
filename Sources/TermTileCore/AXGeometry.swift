import CoreGraphics

/// Cocoa (bottom-left origin) → AX (top-left origin) coordinate flip for a window frame.
///
/// macOS Accessibility global coordinates put (0,0) at the top-left of the ORIGIN screen with
/// y growing DOWNWARD; NSScreen/Cocoa put (0,0) at the bottom-left with y growing UP.
/// `TileLayout.frames` is coordinate-agnostic (ADR-0001: "the AX top-left vs Cocoa bottom-left
/// flip … are the imperative shell's job, never Core's") and must be fed an AX visibleFrame —
/// this pure flip is that bridge. Kept in Core because it is CoreGraphics-only geometry with no
/// AX/AppKit dependency, so it stays unit-testable and `core-purity.sh`-clean; the adapter (#19a)
/// supplies the `displayHeight`.
///
/// `displayHeight` MUST be the ORIGIN screen's full height in POINTS
/// (`NSScreen.screens.first?.frame.height`) — never `NSScreen.main` (that is the key-window's
/// screen and moves with focus) and never a pixel dimension (a Retina panel's 2234px ≠ its
/// ~1117pt logical height). Multi-display flip correctness (a non-origin display has its own
/// offset) is deferred to #15; #19a targets the single origin screen.
public enum AXGeometry {
    /// Convert a Cocoa-space rect to AX top-left space given the origin screen's point height.
    /// The top edge in AX is `displayHeight - cocoa.maxY`; x / width / height pass through.
    /// The transform is its own inverse (an involution) for a fixed `displayHeight`.
    public static func axFrame(fromCocoa cocoa: CGRect, displayHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX,
               y: displayHeight - cocoa.maxY,
               width: cocoa.width,
               height: cocoa.height)
    }
}
