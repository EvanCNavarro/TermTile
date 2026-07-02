import Testing
@testable import TermTileCore

// Spike #7: the PURE resolver for macOS Sequoia native-tiling preference state. Tests the
// nil→OS-default / present→value semantics and the "any user-drag auto-snap path active"
// predicate. The live read of com.apple.WindowManager lives in AXProbe (Kit-side); this
// resolver stays a pure function so it is exhaustively testable. Findings:
// docs/research/spikes/07-native-tiling-interference.md
@Suite("NativeTilingSettings — Sequoia tiling toggle resolver")
struct NativeTilingSettingsTests {
    @Test("absent key resolves to the OS default (enabled) for every toggle")
    func absentResolvesToDefault() {
        for toggle in NativeTilingToggle.allCases {
            #expect(NativeTilingSettings.isEnabled(toggle, storedValue: nil) == toggle.defaultEnabled)
        }
    }

    @Test("all four toggles ship enabled on Sequoia")
    func defaultsAreEnabled() {
        for toggle in NativeTilingToggle.allCases {
            #expect(toggle.defaultEnabled == true)
        }
    }

    @Test("an explicit stored value overrides the default, both ways")
    func explicitValueHonored() {
        #expect(NativeTilingSettings.isEnabled(.dragToEdge, storedValue: false) == false)
        #expect(NativeTilingSettings.isEnabled(.dragToEdge, storedValue: true) == true)
        #expect(NativeTilingSettings.isEnabled(.tiledMargins, storedValue: false) == false)
    }

    @Test("the four toggles map to the grounded com.apple.WindowManager key names")
    func rawValuesMatchGroundedKeys() {
        #expect(NativeTilingToggle.allCases.count == 4)
        #expect(NativeTilingToggle.dragToEdge.rawValue == "EnableTilingByEdgeDrag")
        #expect(NativeTilingToggle.dragToTop.rawValue == "EnableTopTilingByEdgeDrag")
        #expect(NativeTilingToggle.optionAccelerator.rawValue == "EnableTilingOptionAccelerator")
        #expect(NativeTilingToggle.tiledMargins.rawValue == "EnableTiledWindowMargins")
    }

    @Test("all keys absent → every default-on snap path is active")
    func allAbsentAnySnapActive() {
        #expect(NativeTilingSettings.anyAutoSnapPathActive([:]) == true)
    }

    @Test("all three drag paths disabled → no auto-snap path active")
    func allDragPathsDisabled() {
        let stored: [NativeTilingToggle: Bool?] = [
            .dragToEdge: false, .dragToTop: false, .optionAccelerator: false
        ]
        #expect(NativeTilingSettings.anyAutoSnapPathActive(stored) == false)
    }

    @Test("tiledMargins is cosmetic — it never counts as an auto-snap path")
    func marginsDoNotCount() {
        let stored: [NativeTilingToggle: Bool?] = [
            .dragToEdge: false, .dragToTop: false, .optionAccelerator: false, .tiledMargins: true
        ]
        #expect(NativeTilingSettings.anyAutoSnapPathActive(stored) == false)
    }

    @Test("a single enabled drag path keeps auto-snap active")
    func oneDragPathActive() {
        let stored: [NativeTilingToggle: Bool?] = [
            .dragToEdge: false, .dragToTop: true, .optionAccelerator: false
        ]
        #expect(NativeTilingSettings.anyAutoSnapPathActive(stored) == true)
    }
}
