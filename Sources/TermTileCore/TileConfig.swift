import CoreGraphics

/// The inputs a retile decision needs (ADR-0001 rule 1 — pure policy, no AX). `visibleFrame`
/// is supplied in the TARGET (AX top-left) coordinate space by the imperative shell's adapter
/// (#19); Core stays coordinate-agnostic. The per-app min-size clamp (spike-04 73×67) and the
/// coordinate flip are the adapter's job, never Core's.
public struct TileConfig: Equatable, Sendable {
    /// Master switch. `false` = the tiler is inert — the reducer emits no commands at all
    /// (spec-draft: "Off = no rigid behavior at all").
    public var isEnabled: Bool
    /// The active display's visible frame the grid subdivides, in target coordinates.
    public var visibleFrame: CGRect
    /// Uniform gutter on every outer edge and between adjacent cells.
    public var gap: CGFloat

    public init(isEnabled: Bool, visibleFrame: CGRect, gap: CGFloat) {
        self.isEnabled = isEnabled
        self.visibleFrame = visibleFrame
        self.gap = gap
    }

    /// The fail-safe default: tiling off. `WindowStateReducer.reduce` defaults to this so a
    /// caller who forgets to pass a config causes NO surprise window moves.
    public static let disabled = TileConfig(isEnabled: false, visibleFrame: .zero, gap: 0)
}
