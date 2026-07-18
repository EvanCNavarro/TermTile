import CoreGraphics

/// Pure frame comparison for tiling verdicts: did a window land where we asked,
/// within a per-component tolerance (inclusive)? Seed of #9's frame±epsilon
/// expectation ledger. Observed basis: spike 04 (docs/research/spikes/04-frame-writes.md).
public enum FrameMath {
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
        abs(a.origin.x - b.origin.x) <= epsilon
            && abs(a.origin.y - b.origin.y) <= epsilon
            && abs(a.size.width - b.size.width) <= epsilon
            && abs(a.size.height - b.size.height) <= epsilon
    }
}
