import Foundation
@testable import TermTileKit
import Testing

/// #12a — the settings-persistence port. Two live-UserDefaults tests use DISTINCT suite names
/// (Swift Testing parallelizes `@Test`s by default — a shared suite would race, audit F5) and
/// `defer`-guaranteed cleanup so an early `#require` exit never leaks the suite.
@Suite("Settings persistence — AppSettings + SettingsStore")
struct SettingsStoreTests {
    @Test("AppSettings.defaults targets iTerm2 (the documented MVP default)")
    func defaultsAreITerm2() {
        #expect(AppSettings.defaults.targetBundleID == "com.googlecode.iterm2")
    }

    @Test("in-memory fake returns .defaults before any save")
    func fakeDefaultsBeforeSave() {
        #expect(InMemorySettingsStore().load() == .defaults)
    }

    @Test("in-memory fake round-trips a saved value")
    func fakeRoundTrip() {
        let store = InMemorySettingsStore()
        let saved = AppSettings(targetBundleID: "com.mitchellh.ghostty")
        store.save(saved)
        #expect(store.load() == saved)
    }

    @Test("UserDefaults store persists across distinct instances on the same suite")
    func userDefaultsCrossInstanceRoundTrip() {
        let suite = "dev.ecn.apps.termtile.tests.roundtrip"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let saved = AppSettings(targetBundleID: "com.mitchellh.ghostty")
        UserDefaultsSettingsStore(suiteName: suite).save(saved)

        let loaded = UserDefaultsSettingsStore(suiteName: suite).load()   // a NEW instance
        #expect(loaded == saved)
    }

    @Test("absent target key falls back to the default")
    func absentKeyFallsBack() {
        let suite = "dev.ecn.apps.termtile.tests.fallback"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let loaded = UserDefaultsSettingsStore(suiteName: suite).load()   // empty suite
        #expect(loaded.targetBundleID == AppSettings.defaults.targetBundleID)   // absent → default
    }
}
