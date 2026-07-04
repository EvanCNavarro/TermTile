import Carbon.HIToolbox
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
        let saved = AppSettings(targetBundleID: "com.mitchellh.ghostty", wasTrusted: false, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap)
        store.save(saved)
        #expect(store.load() == saved)
    }

    @Test("UserDefaults store persists across distinct instances on the same suite")
    func userDefaultsCrossInstanceRoundTrip() {
        let suite = "dev.ecn.apps.termtile.tests.roundtrip"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let saved = AppSettings(targetBundleID: "com.mitchellh.ghostty", wasTrusted: false, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap)
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

    // #22b — purge() removes the whole persisted domain (so an uninstall's trashed prefs plist can't
    // be resurrected by cfprefsd on the next flush). After purge, the domain is empty and load()
    // falls back to defaults.
    @Test("purge clears the persisted domain")
    func purgeClearsDomain() {
        let suite = "dev.ecn.apps.termtile.tests.purge"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(suiteName: suite)
        store.save(AppSettings(targetBundleID: "com.example.other", wasTrusted: false, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        #expect(store.load().targetBundleID == "com.example.other")

        store.purge()

        #expect(store.load() == .defaults)   // domain cleared → per-key defaults
        #expect((UserDefaults(suiteName: suite)?.persistentDomain(forName: suite) ?? [:]).isEmpty)
    }

    @Test("in-memory fake purge resets to defaults")
    func inMemoryPurge() {
        let store = InMemorySettingsStore()
        store.save(AppSettings(targetBundleID: "com.example.other", wasTrusted: true, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        store.purge()
        #expect(store.load() == .defaults)
    }

    // #23 — wasTrusted persists (distinguishes first-grant from a broken grant). Absent → false
    // (defaults + migrating users); round-trips true across distinct instances.
    @Test("defaults.wasTrusted is false")
    func defaultsWasTrustedFalse() {
        #expect(AppSettings.defaults.wasTrusted == false)
    }

    @Test("wasTrusted absent falls back to false; round-trips true")
    func wasTrustedPersists() {
        let suite = "dev.ecn.apps.termtile.tests.wastrusted"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().wasTrusted == false)   // absent → false
        UserDefaultsSettingsStore(suiteName: suite).save(AppSettings(targetBundleID: "com.x", wasTrusted: true, gap: 8, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().wasTrusted == true)     // new instance
    }

    // #17a — gap persists; absent → 8 (the hard invariant matching the old hardcoded value, so
    // existing users' grids don't reflow on upgrade); round-trips a custom value.
    @Test("defaults.gap is 8 (the upgrade-safe default)")
    func defaultsGapIsEight() {
        #expect(AppSettings.defaults.gap == 8)
    }

    @Test("gap absent falls back to 8; round-trips a custom value")
    func gapPersists() {
        let suite = "dev.ecn.apps.termtile.tests.gap"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().gap == 8)   // absent → 8
        UserDefaultsSettingsStore(suiteName: suite).save(AppSettings(targetBundleID: "com.x", wasTrusted: false, gap: 16, hotKey: .rearrange, reorderOnDrag: false, reorderStrategy: .swap))
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().gap == 16)  // new instance
    }

    // #27 — reorderStrategy persists (as its rawValue); absent → .swap (the intuitive default).
    @Test("reorderStrategy defaults swap; round-trips")
    func reorderStrategyPersists() {
        #expect(AppSettings.defaults.reorderStrategy == .swap)
        let suite = "dev.ecn.apps.termtile.tests.strategy"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().reorderStrategy == .swap)   // absent
        UserDefaultsSettingsStore(suiteName: suite).save(AppSettings(
            targetBundleID: "com.x", wasTrusted: false, gap: 8, hotKey: .rearrange,
            reorderOnDrag: false, reorderStrategy: .rowShift))
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().reorderStrategy == .rowShift)
    }

    // #26 — reorderOnDrag opt-in: absent → false (off by default, so no daemon/permission without
    // the user opting in); round-trips true.
    @Test("reorderOnDrag defaults false; round-trips true")
    func reorderOnDragPersists() {
        #expect(AppSettings.defaults.reorderOnDrag == false)
        let suite = "dev.ecn.apps.termtile.tests.reorder"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().reorderOnDrag == false)   // absent → false
        UserDefaultsSettingsStore(suiteName: suite).save(
            AppSettings(targetBundleID: "com.x", wasTrusted: false, gap: 8, hotKey: .rearrange, reorderOnDrag: true, reorderStrategy: .swap))
        #expect(UserDefaultsSettingsStore(suiteName: suite).load().reorderOnDrag == true)     // new instance
    }

    // #25b — the hotkey round-trips; absent → ⌘⌥T; a tampered NEGATIVE Int must NOT crash load
    // (UInt32(exactly:) → nil → fallback).
    @Test("hotKey absent falls back to ⌘⌥T; round-trips; negative Int is safe")
    func hotKeyPersists() {
        let suite = "dev.ecn.apps.termtile.tests.hotkey"
        func store() -> UserDefaultsSettingsStore { UserDefaultsSettingsStore(suiteName: suite) }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        #expect(store().load().hotKey == .rearrange)                                    // absent → ⌘⌥T
        let custom = HotKeyConfig(keyCode: 15, modifiers: UInt32(controlKey | optionKey))
        store().save(AppSettings(targetBundleID: "com.x", wasTrusted: false, gap: 8, hotKey: custom, reorderOnDrag: false, reorderStrategy: .swap))
        #expect(store().load().hotKey == custom)                                        // round-trip
        UserDefaults(suiteName: suite)?.set(-1, forKey: "hotKeyCode")                    // tamper
        #expect(store().load().hotKey.keyCode == HotKeyConfig.rearrange.keyCode)         // safe fallback
    }
}
