/// The persisted app-shell state the menu-bar UI reads on launch and writes on change — the
/// MVP-user-changeable settings ONLY ("UserDefaults behind a small protocol", remembar-audit
/// §8.7). Deliberately EXCLUDES `launchAtLogin` (whose source of truth is `SMAppService.status`,
/// #12b — persisting it here too would be a double-source-of-truth bug). A pure value type: no
/// Foundation, no AX. Every field's `init` has NO default so a partial write can't silently clobber
/// another field back to a default (the #23 B1 lesson — see `wasTrusted`).
public struct AppSettings: Equatable, Sendable {
    /// The target-app picker selection — the bundle id the AX adapter drives (spec-draft:18).
    public var targetBundleID: String
    /// Whether the user has EVER granted Accessibility (#23). Latched true on first-observed trust;
    /// distinguishes a first-time grant (`needsFirstGrant`) from a BROKEN grant (`grantBroken` —
    /// untrusted but previously granted, e.g. a moved/duplicate bundle). Absent key → false (first
    /// run + migrating users).
    public var wasTrusted: Bool
    /// Tile gap in points (#17a). Stored as `Double` (`CGFloat` isn't UserDefaults-native; the two
    /// are the same 64-bit type). Absent key → 8, the value the shell hardcoded pre-#17a, so an
    /// existing user's grid does NOT reflow on upgrade. The VM clamps writes to `gapRange`.
    public var gap: Double

    public init(targetBundleID: String, wasTrusted: Bool, gap: Double) {
        self.targetBundleID = targetBundleID
        self.wasTrusted = wasTrusted
        self.gap = gap
    }

    /// The launch defaults: target iTerm2 (spec-draft:18; bundle id verified `com.googlecode.iterm2`
    /// via `mdls`), never granted, 8-pt gap. `load()` falls back to these per-key.
    public static let defaults = AppSettings(targetBundleID: "com.googlecode.iterm2", wasTrusted: false, gap: 8)
}
