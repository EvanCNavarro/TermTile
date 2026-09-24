import Testing
@testable import TermTileCore

@Suite("Panel high-water-mark sizing")
struct PanelSizingTests {
    @Test("shrinks to the measured content height when the window is taller")
    func shrinksToContent() {
        #expect(PanelSizing.shrinkTarget(currentHeight: 823, measuredContentHeight: 742) == 742)
    }

    @Test("leaves the window alone when it already fits")
    func fitsAlready() {
        #expect(PanelSizing.shrinkTarget(currentHeight: 742, measuredContentHeight: 742) == nil)
    }

    @Test("never grows — SwiftUI owns the way up")
    func neverGrows() {
        #expect(PanelSizing.shrinkTarget(currentHeight: 742, measuredContentHeight: 900) == nil)
    }

    @Test("an unmeasured content height is not a height")
    func unmeasuredIsIgnored() {
        #expect(PanelSizing.shrinkTarget(currentHeight: 823, measuredContentHeight: 0) == nil)
        #expect(PanelSizing.shrinkTarget(currentHeight: 823, measuredContentHeight: -5) == nil)
    }

    @Test("sub-pixel differences are noise, not a resize")
    func subPixelNoise() {
        #expect(PanelSizing.shrinkTarget(currentHeight: 823, measuredContentHeight: 822.4) == nil)
    }
}
