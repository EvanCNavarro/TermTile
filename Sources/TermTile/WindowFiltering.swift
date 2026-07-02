/// Pure predicate deciding whether an enumerated AX window participates in tiling.
/// Inputs are optionals because AX attribute reads can fail per-window on some apps;
/// a failed read fails CLOSED (not tileable) rather than tiling an unknown window.
/// Observed basis: spike 03 (docs/research/spikes/03-iterm2-window-enumeration.md).
enum WindowFiltering {
    /// The kAXSubroleAttribute value of a normal, tileable document window.
    static let standardSubrole = "AXStandardWindow"

    static func isTileable(subrole: String?, isMinimized: Bool?, isFullscreen: Bool?) -> Bool {
        subrole == standardSubrole && isMinimized == false && isFullscreen == false
    }
}
