// Spike #7: pure resolver for macOS Sequoia (15.x) native window-tiling preferences.
// Grounded on macOS 15.1 (build 24B83): the four toggles live under the
// `com.apple.WindowManager` defaults domain and are ABSENT by default (verified via
// `defaults read` this session), so an absent key means the OS default (enabled). The live
// read of the domain lives in AXProbe (Kit-side, CFPreferences); THIS type stays a pure
// function of already-read values so it is exhaustively unit-testable — no Foundation, no
// AppKit/ApplicationServices (ADR-0001 core purity). Findings:
// docs/research/spikes/07-native-tiling-interference.md

/// A macOS Sequoia native-tiling toggle. `rawValue` is the exact `com.apple.WindowManager`
/// preference key (grounded via `defaults read` — see the spike note). Only the first three
/// are USER-DRAG auto-snap paths that could relocate a window out from under TermTile's
/// layout; `tiledMargins` is cosmetic (gaps between already-tiled windows).
public enum NativeTilingToggle: String, CaseIterable, Sendable {
    /// Drag a window to a screen edge to tile it. System Settings › Desktop & Dock ›
    /// "Drag windows to screen edges to tile".
    case dragToEdge = "EnableTilingByEdgeDrag"
    /// Drag a window to the menu bar to fill the screen. "Drag windows to menu bar to fill".
    case dragToTop = "EnableTopTilingByEdgeDrag"
    /// Hold Option while dragging to tile. "Hold [Option] key while dragging windows to tile".
    case optionAccelerator = "EnableTilingOptionAccelerator"
    /// Cosmetic margins between tiled windows. "Tiled windows have margins". NOT an
    /// auto-snap path — it cannot relocate a window.
    case tiledMargins = "EnableTiledWindowMargins"

    /// The OS-shipped default when the key is absent. All four ship enabled on Sequoia
    /// (`dragToEdge` confirmed empirically: drag-to-edge tiling is active with the key
    /// absent; the other three are Apple-documented defaults — see the spike note).
    public var defaultEnabled: Bool { true }

    /// The user-drag auto-snap paths — the toggles whose being ON means a user gesture can
    /// snap-tile a window (and thus move it out from under TermTile's layout). Excludes the
    /// cosmetic `tiledMargins`.
    public static var autoSnapPaths: [NativeTilingToggle] {
        [.dragToEdge, .dragToTop, .optionAccelerator]
    }
}

/// Pure resolution of Sequoia native-tiling preference state. No I/O; the caller supplies
/// already-read values (`nil` = key absent = OS default).
public enum NativeTilingSettings {
    /// Resolve a toggle's effective state. `storedValue == nil` (key absent) → the OS
    /// default; a present value is honored verbatim.
    public static func isEnabled(_ toggle: NativeTilingToggle, storedValue: Bool?) -> Bool {
        storedValue ?? toggle.defaultEnabled
    }

    /// Whether ANY user-drag auto-snap path is currently active — i.e. whether a user
    /// gesture could snap-tile a managed window. Absent keys default-on (`isEnabled`).
    /// `tiledMargins` is excluded (cosmetic, cannot relocate a window).
    public static func anyAutoSnapPathActive(_ stored: [NativeTilingToggle: Bool?]) -> Bool {
        NativeTilingToggle.autoSnapPaths.contains { toggle in
            isEnabled(toggle, storedValue: stored[toggle] ?? nil)
        }
    }
}
