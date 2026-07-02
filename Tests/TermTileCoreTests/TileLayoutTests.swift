import CoreGraphics
import Testing
@testable import TermTileCore

/// Column-of-2 layout math (spec-draft.md:20-22): N windows → columns = ceil(N/2),
/// each column stacks ≤2 windows, last column holds 1 (full height) when N is odd,
/// equal widths, rows split height evenly, uniform gap gutter on every edge and between.
@Suite("TileLayout — column-of-2 tiling")
struct TileLayoutTests {
    // Realistic single-display visible frame + gap (the frame #10 will actually feed).
    static let vf = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let gap: CGFloat = 8
    static let eps: CGFloat = 1e-9

    static func expectedColumns(_ n: Int) -> Int { (n + 1) / 2 }

    // T1: correct count, and distinct x-origins == ceil(N/2) columns, for N=1..12.
    @Test("frame count == N and column count == ceil(N/2)", arguments: 1...12)
    func countAndColumns(n: Int) {
        let frames = TileLayout.frames(count: n, visibleFrame: Self.vf, gap: Self.gap)
        #expect(frames.count == n)
        let distinctX = Set(frames.map { ($0.minX / Self.eps).rounded() })
        #expect(distinctX.count == Self.expectedColumns(n))
    }

    // T2: all columns share one width (equal widths), for N=1..12.
    @Test("all frames share one width", arguments: 1...12)
    func equalWidths(n: Int) {
        let frames = TileLayout.frames(count: n, visibleFrame: Self.vf, gap: Self.gap)
        let w0 = frames[0].width
        #expect(frames.allSatisfy { abs($0.width - w0) < Self.eps })
    }

    // T3: column-major slot order — frame[0] & frame[1] share a column; row 1 has
    // greater y (shell owns the top/bottom flip); frame[2] starts a new column (larger x).
    @Test("slot order is column-major (fill each column top→bottom, then next column)")
    func columnMajorOrder() {
        let frames = TileLayout.frames(count: 3, visibleFrame: Self.vf, gap: Self.gap)
        #expect(abs(frames[0].minX - frames[1].minX) < Self.eps) // same column
        #expect(frames[1].minY > frames[0].minY)                 // row 1 greater y
        #expect(frames[2].minX > frames[0].minX)                 // next column, larger x
    }

    // T4 + F5: lone-last-odd column is FULL interior height (H-2g); an even-N column's
    // window is the exact 2-row height (H-3g)/2 — NOT a loose "≈".
    @Test("lone last column (odd N) is full height; paired column is exact 2-row height")
    func rowHeights() {
        let full = Self.vf.height - 2 * Self.gap
        let twoRow = (Self.vf.height - 3 * Self.gap) / 2
        // Odd N=5: last frame is the lone window in the last column → full height.
        let odd = TileLayout.frames(count: 5, visibleFrame: Self.vf, gap: Self.gap)
        #expect(abs(odd.last!.height - full) < Self.eps)
        // Even N=4: every frame is in a 2-window column → exact 2-row height.
        let even = TileLayout.frames(count: 4, visibleFrame: Self.vf, gap: Self.gap)
        #expect(even.allSatisfy { abs($0.height - twoRow) < Self.eps })
    }

    // F5: the vertical gutter between the two stacked windows of a column is exactly `gap`.
    @Test("stacked windows in a column are separated by exactly one gap")
    func verticalGap() {
        let frames = TileLayout.frames(count: 2, visibleFrame: Self.vf, gap: Self.gap)
        #expect(abs(frames[1].minY - frames[0].maxY - Self.gap) < Self.eps)
    }

    // T5: coverage/bounds — col 0 left edge == minX+g; last column right edge == maxX-g;
    // adjacent columns separated by exactly one gap; every frame inset ≥ g on all sides.
    @Test("columns cover the frame with uniform gap gutters", arguments: 1...12)
    func coverageAndGaps(n: Int) {
        let frames = TileLayout.frames(count: n, visibleFrame: Self.vf, gap: Self.gap)
        let xs = frames.map(\.minX).sorted()
        let firstColX = xs.first!
        let lastCol = frames.max(by: { $0.minX < $1.minX })!
        #expect(abs(firstColX - (Self.vf.minX + Self.gap)) < Self.eps)
        #expect(abs(lastCol.maxX - (Self.vf.maxX - Self.gap)) < Self.eps)
        // adjacent distinct columns separated by exactly one gap
        let uniqueX = Array(Set(xs.map { ($0 / Self.eps).rounded() * Self.eps })).sorted()
        let w0 = frames[0].width
        for i in 1..<uniqueX.count {
            #expect(abs(uniqueX[i] - uniqueX[i - 1] - (w0 + Self.gap)) < 1e-6)
        }
        // every frame sits inside the visible frame, inset by at least the gap
        let insetOK: (CGRect) -> Bool = { f in
            let leftOK: Bool = f.minX >= Self.vf.minX + Self.gap - Self.eps
            let rightOK: Bool = f.maxX <= Self.vf.maxX - Self.gap + Self.eps
            let topOK: Bool = f.minY >= Self.vf.minY + Self.gap - Self.eps
            let bottomOK: Bool = f.maxY <= Self.vf.maxY - Self.gap + Self.eps
            return leftOK && rightOK && topOK && bottomOK
        }
        #expect(frames.allSatisfy(insetOK))
    }

    // T6: gap == 0 → columns tile edge-to-edge with no gutters.
    @Test("gap 0 tiles edge to edge")
    func zeroGap() {
        let frames = TileLayout.frames(count: 4, visibleFrame: Self.vf, gap: 0)
        #expect(abs(frames.map(\.minX).min()! - Self.vf.minX) < Self.eps)
        #expect(abs(frames.map(\.maxX).max()! - Self.vf.maxX) < Self.eps)
        #expect(abs(frames.map(\.minY).min()! - Self.vf.minY) < Self.eps)
        #expect(abs(frames.map(\.maxY).max()! - Self.vf.maxY) < Self.eps)
    }

    // F6: no two frames overlap, for N=1..12. The backstop that proves we tiled the plane —
    // a column-major/off-by-one slot bug beyond index 2 would double-book and be caught here.
    @Test("no two frames overlap", arguments: 1...12)
    func noOverlap(n: Int) {
        let frames = TileLayout.frames(count: n, visibleFrame: Self.vf, gap: Self.gap)
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                #expect(!frames[i].insetBy(dx: Self.eps, dy: Self.eps)
                    .intersects(frames[j].insetBy(dx: Self.eps, dy: Self.eps)))
            }
        }
    }

    // F7: realistic inputs never produce inverted/degenerate rects.
    @Test("all frames have positive width and height", arguments: 1...12)
    func positiveDimensions(n: Int) {
        let frames = TileLayout.frames(count: n, visibleFrame: Self.vf, gap: Self.gap)
        #expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    // T7: math holds for a negative-origin visible frame (multi-display global coords).
    @Test("negative-origin visible frame tiles correctly")
    func negativeOrigin() {
        let vf = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let frames = TileLayout.frames(count: 3, visibleFrame: vf, gap: Self.gap)
        #expect(frames.count == 3)
        #expect(abs(frames.map(\.minX).min()! - (vf.minX + Self.gap)) < Self.eps)
        #expect(frames.allSatisfy { vf.insetBy(dx: -Self.eps, dy: -Self.eps).contains($0) })
    }

    // T8: count == 0 → no frames (and negatives don't crash).
    @Test("non-positive count yields no frames")
    func emptyCount() {
        #expect(TileLayout.frames(count: 0, visibleFrame: Self.vf, gap: Self.gap).isEmpty)
        #expect(TileLayout.frames(count: -3, visibleFrame: Self.vf, gap: Self.gap).isEmpty)
    }
}
