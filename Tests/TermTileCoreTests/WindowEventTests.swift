import Testing
@testable import TermTileCore

@Suite("WindowEventKind")
struct WindowEventTests {
    // The AX notification vocabulary the observer registers for (spike 05); the
    // mapping is the seed of #9's WindowEvent model.
    @Test("known AX notification names map to their kind",
          arguments: [
            ("AXWindowCreated", WindowEventKind.created),
            ("AXWindowMoved", WindowEventKind.moved),
            ("AXWindowResized", WindowEventKind.resized),
            ("AXUIElementDestroyed", WindowEventKind.destroyed),
          ])
    func knownNames(name: String, expected: WindowEventKind) {
        #expect(WindowEventKind(axNotification: name) == expected)
    }

    @Test("unregistered or malformed names map to nil",
          arguments: ["AXFocusedWindowChanged", "AXTitleChanged", "", "axwindowcreated"])
    func unknownNames(name: String) {
        #expect(WindowEventKind(axNotification: name) == nil)
    }
}
