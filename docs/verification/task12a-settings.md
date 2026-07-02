# Task #12a — Settings persistence port (verification)

**Date:** 2026-07-03 · **Branch:** loop/phase-a · **Plan:** `.engine/state/stoke-plan-12a.md`

## What landed
Split from #12 (menu-bar app shell) by stoke-plan-12a.md into #12a/#12b/#12c. This beat is
**#12a — the settings-persistence seam**:

- `Sources/TermTileKit/AppSettings.swift` — pure value type `AppSettings { isEnabled: Bool;
  targetBundleID: String }` + `.defaults` (off, `com.googlecode.iterm2`). Persists ONLY the two
  MVP-user-changeable settings; `gap` (hardcoded → #17) and `launchAtLogin` (source of truth =
  `SMAppService.status`, #12b) are deliberately excluded (no double-source-of-truth).
- `Sources/TermTileKit/SettingsStore.swift` — `SettingsStore` protocol (sync `load`/`save`) +
  `UserDefaultsSettingsStore` (stores only `suiteName: String?` so it stays `Sendable` under
  Swift 6 — `UserDefaults` itself is non-Sendable; reads each key independently via
  `object`/`string(forKey:)` with per-key fallback to `.defaults`).
- `Tests/TermTileKitTests/{SettingsStoreTests,InMemorySettingsStore}.swift` — 5 tests + a
  lock-guarded `@unchecked Sendable` fake (a `SettingsStore` requirement is synchronous → the
  fake cannot be an `actor`).
- `Sources/AXProbe/main.swift` — throwaway-but-committed `settingscheck <suite>` verb driving the
  REAL `UserDefaultsSettingsStore` for the external-process live PROVE (project convention).

## PROVE (FL-1)
Live surface = UserDefaults persistence (no AX/GUI — that is #12c).

1. **`swift test` → 107 tests passed** (102 prior + 5 new), incl. a LIVE
   `UserDefaults(suiteName:)` cross-instance round-trip and a per-key independent-fallback test.
2. **Invert-check** (keystone invert = break `load()` → `.defaults`, run as SEPARATE commands,
   TRAP-9): tests 4 & 5 reddened for the right reason, verbatim —
   - `Expectation failed: (loaded → AppSettings(isEnabled: false, targetBundleID: "com.googlecode.iterm2")) == (saved → AppSettings(isEnabled: true, targetBundleID: "com.mitchellh.ghostty"))`
   - `Expectation failed: (loaded.isEnabled → false) == true`
   - restored → 107/107 green.
3. **External-process live persistence proof** — the REAL product code (`UserDefaultsSettingsStore`
   via `AXProbe settingscheck`) wrote to the actual macOS defaults DB, and a SEPARATE process
   (`defaults read`) observed the exact bytes:
   ```
   settingscheck: suite=dev.ecn.apps.termtile.prove12a saved=AppSettings(isEnabled: true, targetBundleID: "com.mitchellh.ghostty") loaded=AppSettings(isEnabled: true, targetBundleID: "com.mitchellh.ghostty") PASS=true
   $ defaults read dev.ecn.apps.termtile.prove12a
   {
       isEnabled = 1;
       targetBundleID = "com.mitchellh.ghostty";
   }
   ```
   Wrong-thing-didn't-happen: `isEnabled = 1` (not the `0`/iTerm2 default). Suite deleted after —
   no pollution.
4. All 7 `.engine/checks/*.sh` PASS (core-purity: no Core touched — AppSettings/SettingsStore are
   Kit; axprobe-no-defer + axprobe-detached-task: `settingscheck` uses neither `defer` nor a bare
   `Task {`).

## Deferred to downstream tasks (already in the BACKLOG, not new)
- #12b — launch-at-login (`SMAppService.mainApp` behind a `LoginItem` protocol); LIVE registration
  needs the bundled `.app` → `[DEP: blocked-by #13]`.
- #12c — MenuBarExtra shell wiring (toggle→`TilingActor.activate`, target-app picker, permission
  fix-it row); PROVE = live app launch + AX menu-bar enumeration (TRAP-1), blocked-by #12a/#12b/#19b.
