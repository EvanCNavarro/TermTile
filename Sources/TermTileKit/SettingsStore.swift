import Foundation

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
            isEnabled: d.object(forKey: Key.isEnabled) as? Bool ?? AppSettings.defaults.isEnabled,
            targetBundleID: d.string(forKey: Key.targetBundleID) ?? AppSettings.defaults.targetBundleID)
    }

    public func save(_ settings: AppSettings) {
        let d = defaults
        d.set(settings.isEnabled, forKey: Key.isEnabled)
        d.set(settings.targetBundleID, forKey: Key.targetBundleID)
    }

    /// The UserDefaults key names — the persistence contract (also raw-referenced by the
    /// per-key-fallback test).
    private enum Key {
        static let isEnabled = "isEnabled"
        static let targetBundleID = "targetBundleID"
    }
}
