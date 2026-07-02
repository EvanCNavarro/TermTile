import Testing
@testable import TermTile

@Suite("WindowFiltering")
struct WindowFilteringTests {
    // Full truth table (audit N4): only standard + explicitly-unminimized +
    // explicitly-unfullscreened is tileable; nil (attribute read failed) fails closed.
    @Test("only a standard, unminimized, unfullscreened window is tileable",
          arguments: [
            (WindowFiltering.standardSubrole, false, false, true),
            (WindowFiltering.standardSubrole, false, true, false),
            (WindowFiltering.standardSubrole, true, false, false),
            (WindowFiltering.standardSubrole, true, true, false),
            ("AXDialog", false, false, false),
            ("AXFloatingWindow", false, false, false),
            ("AXSystemDialog", true, false, false),
            ("AXUnknown", false, true, false),
          ] as [(String, Bool, Bool, Bool)])
    func truthTable(subrole: String, minimized: Bool, fullscreen: Bool, expected: Bool) {
        #expect(WindowFiltering.isTileable(
            subrole: subrole, isMinimized: minimized, isFullscreen: fullscreen) == expected)
    }

    @Test("nil attribute reads fail closed",
          arguments: [
            (nil, false, false),
            (WindowFiltering.standardSubrole, nil, false),
            (WindowFiltering.standardSubrole, false, nil),
            (nil, nil, nil),
          ] as [(String?, Bool?, Bool?)])
    func failClosed(subrole: String?, minimized: Bool?, fullscreen: Bool?) {
        #expect(WindowFiltering.isTileable(
            subrole: subrole, isMinimized: minimized, isFullscreen: fullscreen) == false)
    }
}
