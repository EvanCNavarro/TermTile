import CoreGraphics

/// Pure column-of-2 tiling math (ADR-0001 rule 1 — the functional core). Spec basis:
/// docs/product/spec-draft.md:20-22 — N visible windows → `columns = ceil(N/2)`, each
/// column stacks up to 2 windows, the last column holds 1 (full column height) when N is
/// odd, all columns equal width, rows split the visible frame height evenly, with a uniform
/// `gap` gutter on every outer edge and between adjacent cells.
public enum TileLayout {
    /// Frames for `count` windows within `visibleFrame`, column-major slot order:
    /// `frame[k]` occupies column `k / 2`, row `k % 2` (top row = index 0, which sits at
    /// `visibleFrame.minY`). Coordinate-system agnostic pure subdivision — the AX top-left
    /// vs Cocoa bottom-left flip and app-minimum-size clamping (spike-04 73×67) are the
    /// imperative shell's job (#10), never Core's. `count <= 0` → `[]`.
    public static func frames(count: Int, visibleFrame: CGRect, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }

        let columns = (count + 1) / 2 // ceil(count / 2)
        let columnWidth = (visibleFrame.width - gap * CGFloat(columns + 1)) / CGFloat(columns)

        return (0..<count).map { k in
            let column = k / 2
            let rowInColumn = k % 2
            let isLoneLast = column == columns - 1 && count % 2 == 1
            let rowsHere = isLoneLast ? 1 : 2

            let rowHeight = (visibleFrame.height - gap * CGFloat(rowsHere + 1)) / CGFloat(rowsHere)
            let x = visibleFrame.minX + gap + CGFloat(column) * (columnWidth + gap)
            let y = visibleFrame.minY + gap + CGFloat(rowInColumn) * (rowHeight + gap)

            return CGRect(x: x, y: y, width: columnWidth, height: rowHeight)
        }
    }
}
