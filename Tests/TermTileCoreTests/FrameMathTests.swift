import CoreGraphics
import Testing
@testable import TermTileCore

@Suite("FrameMath")
struct FrameMathTests {
    static let base = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test("identical frames match at epsilon 0")
    func exactMatch() {
        #expect(FrameMath.approximatelyEqual(Self.base, Self.base, epsilon: 0))
    }

    // Per-component drift strictly under epsilon still matches (AX readbacks jitter
    // by sub-point amounts; spike-04 verdicts must not flap on that).
    @Test("each component off by less than epsilon matches",
          arguments: [
            CGRect(x: 100.5, y: 100, width: 800, height: 600),
            CGRect(x: 100, y: 99.5, width: 800, height: 600),
            CGRect(x: 100, y: 100, width: 800.5, height: 600),
            CGRect(x: 100, y: 100, width: 800, height: 599.5),
          ])
    func withinEpsilon(candidate: CGRect) {
        #expect(FrameMath.approximatelyEqual(Self.base, candidate, epsilon: 1.0))
    }

    @Test("drift of exactly epsilon still matches (inclusive bound)")
    func inclusiveBound() {
        let shifted = CGRect(x: 101, y: 100, width: 800, height: 600)
        #expect(FrameMath.approximatelyEqual(Self.base, shifted, epsilon: 1.0))
    }

    @Test("any single component beyond epsilon fails the match",
          arguments: [
            CGRect(x: 102, y: 100, width: 800, height: 600),
            CGRect(x: 100, y: 98, width: 800, height: 600),
            CGRect(x: 100, y: 100, width: 803, height: 600),
            CGRect(x: 100, y: 100, width: 800, height: 597),
          ])
    func beyondEpsilon(candidate: CGRect) {
        #expect(!FrameMath.approximatelyEqual(Self.base, candidate, epsilon: 1.0))
    }

    // Multi-display arrangements put windows at negative global coordinates; the
    // comparator must be sign-agnostic even though this Mac has one display (audit F8).
    @Test("negative-coordinate frames compare correctly")
    func negativeCoordinates() {
        let left = CGRect(x: -1440, y: -200, width: 720, height: 450)
        let near = CGRect(x: -1440.4, y: -200.4, width: 720.4, height: 450.4)
        let far = CGRect(x: -1445, y: -200, width: 720, height: 450)
        #expect(FrameMath.approximatelyEqual(left, near, epsilon: 0.5))
        #expect(!FrameMath.approximatelyEqual(left, far, epsilon: 0.5))
    }
}
