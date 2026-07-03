/// The persisted app-shell state the menu-bar UI reads on launch and writes on change — the
/// MVP-user-changeable settings ONLY ("UserDefaults behind a small protocol", remembar-audit
/// §8.7). Deliberately EXCLUDES `gap` (a hardcoded sane constant until the gap UI lands, #17)
/// and `launchAtLogin` (whose source of truth is `SMAppService.status`, #12b — persisting it
/// here too would be a double-source-of-truth bug). A pure value type: no Foundation, no AX.
public struct AppSettings: Equatable, Sendable {
    /// The target-app picker selection — the bundle id the AX adapter drives (spec-draft:18).
    public var targetBundleID: String

    public init(targetBundleID: String) {
        self.targetBundleID = targetBundleID
    }

    /// The launch default: target iTerm2 (spec-draft:18 "default iTerm2"; bundle id verified
    /// `com.googlecode.iterm2` via `mdls`). `load()` falls back to these per-key.
    public static let defaults = AppSettings(targetBundleID: "com.googlecode.iterm2")
}
