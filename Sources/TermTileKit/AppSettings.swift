/// The persisted app-shell state the menu-bar UI reads on launch and writes on change — the
/// MVP-user-changeable settings ONLY ("UserDefaults behind a small protocol", remembar-audit
/// §8.7). Deliberately EXCLUDES `gap` (a hardcoded sane constant until the gap UI lands, #17)
/// and `launchAtLogin` (whose source of truth is `SMAppService.status`, #12b — persisting it
/// here too would be a double-source-of-truth bug). A pure value type: no Foundation, no AX.
public struct AppSettings: Equatable, Sendable {
    /// The menu toggle. `false` = the tiler is inert (spec-draft:17 "Off = no rigid behavior at
    /// all"); mirrors `TileConfig.disabled`'s fail-safe default.
    public var isEnabled: Bool
    /// The target-app picker selection — the bundle id the AX adapter drives (spec-draft:18).
    public var targetBundleID: String

    public init(isEnabled: Bool, targetBundleID: String) {
        self.isEnabled = isEnabled
        self.targetBundleID = targetBundleID
    }

    /// The launch default: tiling off, targeting iTerm2 (spec-draft:18 "default iTerm2"; bundle
    /// id verified `com.googlecode.iterm2` via `mdls`). `load()` falls back to these per-key.
    public static let defaults = AppSettings(isEnabled: false,
                                             targetBundleID: "com.googlecode.iterm2")
}
