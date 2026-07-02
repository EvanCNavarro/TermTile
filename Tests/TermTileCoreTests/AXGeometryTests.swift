import CoreGraphics
import Testing
@testable import TermTileCore

/// #19a keystone — the pure Cocoa(bottom-left)→AX(top-left) coordinate flip. AX global
/// coordinates put (0,0) at the top-left of the origin screen with y growing DOWNWARD;
/// NSScreen/Cocoa put (0,0) at the bottom-left with y growing UP. `TileLayout` is
/// coordinate-agnostic (ADR-0001) and must be fed an AX visibleFrame — this flip is that
/// bridge, and a wrong SIGN is the classic bug, so the tests pin the sign and the involution.
@Suite("AXGeometry — Cocoa↔AX coordinate flip")
struct AXGeometryTests {
    // A full-screen Cocoa rect on an H-tall origin screen maps to AX (0,0,W,H): maxY == H → axY 0.
    @Test("full-screen: cocoa (0,0,1440,900) on H=900 → AX y=0")
    func fullScreenIdentity() {
        let ax = AXGeometry.axFrame(fromCocoa: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    displayHeight: 900)
        #expect(ax == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    // Menu bar (24pt) at the TOP shrinks Cocoa visibleFrame height to 876 with origin.y 0
    // (Cocoa origin is the BOTTOM); maxY 876 → AX y = 900-876 = 24 (just below the menu bar).
    @Test("menu-bar inset: cocoa (0,0,1440,876) on H=900 → AX y=24 (below menu bar)")
    func menuBarInset() {
        let ax = AXGeometry.axFrame(fromCocoa: CGRect(x: 0, y: 0, width: 1440, height: 876),
                                    displayHeight: 900)
        #expect(ax == CGRect(x: 0, y: 24, width: 1440, height: 876))
    }

    // Dock (70pt) at the BOTTOM raises Cocoa origin.y to 70; maxY still 876 → AX y still 24.
    // Proves the flip keys on maxY (top edge), not minY, and passes x/width/height through.
    @Test("dock at bottom: cocoa (0,70,1440,806) on H=900 → AX (0,24,1440,806)")
    func dockAtBottom() {
        let ax = AXGeometry.axFrame(fromCocoa: CGRect(x: 0, y: 70, width: 1440, height: 806),
                                    displayHeight: 900)
        #expect(ax == CGRect(x: 0, y: 24, width: 1440, height: 806))
    }

    // Non-zero x passes through unchanged; y flips.
    @Test("x passthrough: cocoa (100,0,800,600) on H=900 → AX (100,300,800,600)")
    func xPassthrough() {
        let ax = AXGeometry.axFrame(fromCocoa: CGRect(x: 100, y: 0, width: 800, height: 600),
                                    displayHeight: 900)
        #expect(ax == CGRect(x: 100, y: 300, width: 800, height: 600))
    }

    // The flip is its own inverse: applying it twice returns the original rect (involution).
    @Test("involution: flipping twice is identity")
    func involution() {
        let original = CGRect(x: 33, y: 111, width: 640, height: 480)
        let once = AXGeometry.axFrame(fromCocoa: original, displayHeight: 900)
        let twice = AXGeometry.axFrame(fromCocoa: once, displayHeight: 900)
        #expect(twice == original)
    }
}
