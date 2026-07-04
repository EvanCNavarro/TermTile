import TermTileCore

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
    /// The global "Rearrange now" hotkey (#25b), user-settable via the menu recorder. Stored as its
    /// two `UInt32` fields (keyCode + Carbon modifiers) → 2 Int keys. Absent → ⌘⌥T.
    public var hotKey: HotKeyConfig
    /// Opt-in: reorder a tiled window back into the grid when it's dragged (#26). OFF by default —
    /// only when enabled does the app request Input Monitoring + start the mouse/AX watchers, so the
    /// clean single-permission manual model stays the default. Absent → false.
    public var reorderOnDrag: Bool
    /// How a drag-reorder reshuffles the other windows (#27) — user-selectable. Persisted as its
    /// rawValue; absent → .swap.
    public var reorderStrategy: ReorderStrategy

    public init(targetBundleID: String, wasTrusted: Bool, gap: Double, hotKey: HotKeyConfig,
                reorderOnDrag: Bool, reorderStrategy: ReorderStrategy) {
        self.targetBundleID = targetBundleID
        self.wasTrusted = wasTrusted
        self.gap = gap
        self.hotKey = hotKey
        self.reorderOnDrag = reorderOnDrag
        self.reorderStrategy = reorderStrategy
    }

    /// The launch defaults: target iTerm2 (spec-draft:18; bundle id verified `com.googlecode.iterm2`
    /// via `mdls`), never granted, 8-pt gap, ⌘⌥T hotkey, drag-reorder off, swap reorder. `load()`
    /// falls back per-key.
    public static let defaults = AppSettings(
        targetBundleID: "com.googlecode.iterm2", wasTrusted: false, gap: 8, hotKey: .rearrange,
        reorderOnDrag: false, reorderStrategy: .swap)
}
