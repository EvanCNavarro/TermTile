import Foundation
import TermTileCore

/// The persistence port for `AppSettings` (ADR-0001 imperative-shell seam). The production
/// adapter is `UserDefaultsSettingsStore`; tests inject an in-memory fake. Synchronous by design
/// — settings reads/writes are cheap and non-blocking, so (unlike the `WindowSystem` port) there
/// is no `async`/actor requirement.
public protocol SettingsStore: Sendable {
    /// The persisted settings, with `AppSettings.defaults` substituted per-key for any key never
    /// written.
    func load() -> AppSettings
    /// Persist `settings` (all keys).
    func save(_ settings: AppSettings)
    /// Remove the ENTIRE persisted domain — the uninstall clear (#22b). This lives on the
    /// persistence authority (not the Uninstaller) so "how we own our defaults" has one home. It
    /// also stops `cfprefsd` from resurrecting a separately-trashed prefs plist on the next flush:
    /// `removePersistentDomain` clears the in-memory registration AND the on-disk plist together.
    func purge()
}

/// The production `SettingsStore`, backed by `UserDefaults`. Stores ONLY the `suiteName`
/// (a `Sendable` `String?`) and resolves the `UserDefaults` per call: `UserDefaults` is not
/// `Sendable`, so a stored reference would break the `Sendable` conformance under Swift 6 strict
/// concurrency (stoke-plan-12a audit F1, compiler-verified). `nil` suite → `.standard`
/// (production); a dedicated suite name is injected only by tests.
public struct UserDefaultsSettingsStore: SettingsStore {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// The resolved store: the named suite, or `.standard` when unnamed — never
    /// `UserDefaults(suiteName: nil)`, which Apple documents as misuse.
    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Read each key INDEPENDENTLY via `object`/`string(forKey:)` (NOT `bool(forKey:)`, which
    /// can't distinguish a stored `false` from an absent key), falling back per-key to
    /// `AppSettings.defaults` so a partially-written domain still loads sane values.
    public func load() -> AppSettings {
        let d = defaults
        return AppSettings(
            targetBundleID: d.string(forKey: Key.targetBundleID) ?? AppSettings.defaults.targetBundleID,
            // `object(forKey:) as? Bool` (NOT bool(forKey:)) so an absent key falls back to false
            // rather than reading as a stored false — the per-key discipline this store mandates.
            wasTrusted: d.object(forKey: Key.wasTrusted) as? Bool ?? AppSettings.defaults.wasTrusted,
            gap: d.object(forKey: Key.gap) as? Double ?? AppSettings.defaults.gap,
            // `UInt32(exactly:)` — a tampered negative Int would TRAP `UInt32(_:)`; fall back per-key.
            hotKey: HotKeyConfig(
                keyCode: (d.object(forKey: Key.hotKeyCode) as? Int).flatMap(UInt32.init(exactly:))
                    ?? AppSettings.defaults.hotKey.keyCode,
                modifiers: (d.object(forKey: Key.hotKeyModifiers) as? Int).flatMap(UInt32.init(exactly:))
                    ?? AppSettings.defaults.hotKey.modifiers))
    }

    public func save(_ settings: AppSettings) {
        let d = defaults
        d.set(settings.targetBundleID, forKey: Key.targetBundleID)
        d.set(settings.wasTrusted, forKey: Key.wasTrusted)
        d.set(settings.gap, forKey: Key.gap)
        d.set(Int(settings.hotKey.keyCode), forKey: Key.hotKeyCode)
        d.set(Int(settings.hotKey.modifiers), forKey: Key.hotKeyModifiers)
    }

    /// The domain name is the suite when named (tests) or the app's bundleID for `.standard`
    /// (production, where UserDefaults writes `~/Library/Preferences/<bundleID>.plist`).
    public func purge() {
        defaults.removePersistentDomain(forName: suiteName ?? AppIdentity.bundleID)
    }

    /// The UserDefaults key names — the persistence contract (also raw-referenced by the
    /// per-key-fallback test).
    private enum Key {
        static let targetBundleID = "targetBundleID"
        static let wasTrusted = "wasTrusted"
        static let gap = "gap"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }
}
