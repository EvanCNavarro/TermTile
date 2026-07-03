# Task #12c verification — MenuBarExtra shell wiring (2026-07-03)

Plan: `.engine/state/stoke-plan-12c.md` (S2, skeptic-audited SAFE-WITH-FIXES). Composes the
#12a `SettingsStore`, #12b `LoginItem`, and #19 `AXWindowSystem`/`TilingActor` ports into a
`MenuBarExtra(.window)` shell (toggle · target-app picker · launch-at-login · permission fix-it
row), following the RememBar template (`init()` = reliable delegate hook, `.menuBarExtraStyle`).

## Test evidence (red-first)

- Baseline green: `swift test` → **112 tests passed** (the authoritative runner count; the grep's
  "114 @Test" included 2 non-run annotations — re-baselined per audit R7).
- New Kit suite `MenuBarViewModel — shell wiring` (10 tests) green; full suite **122 tests
  passed**.
- Red-first: the suite referenced `MenuBarViewModel` before it existed →
  `error: cannot find type 'MenuBarViewModel' in scope` (correct compile-red for new code).
- **Invert-check** (FL-1, single flip, separate commands per TRAP-9; `--filter` by FUNCTION name
  `toggleOnPersistsAndTiles` per TRAP-16): broke the keystone wire (`setEnabled` always
  `activate(.disabled)`) →
  `✘ Expectation failed: (writes.count → 0) == 3` and `(Set(writes.map(\.id)) → []) == [2, 3, 1]`
  → restored → re-green (`✔ toggle-on persists and tiles at grid targets passed`).

## Architecture (ADR-0001 functional-core / imperative-shell)

- **Kit (tested over fakes):** `MenuBarViewModel` (`@MainActor @Observable`; binds ports + an
  injected trust probe + a `makeActor` factory + an INJECTED `visibleFrame` so tests are
  deterministic — audit R1); `TargetApp` + `TargetAppsProviding` port; `WorkspaceTargetAppsProvider`
  (NSWorkspace adapter); `InMemoryTargetAppsProvider` fake.
- **Shell (live-proven):** `MenuBarContent` (thin SwiftUI renderer); `TermTileApp` composition
  root (real adapters, `.accessory` policy, `TERMTILE_SELFTEST` hook).
- Toggle-off is inert — `TileEngine.retileCommands:21` `guard config.isEnabled` → `activate`
  emits zero writes (`toggleOffIsInert` pins it). No `run()`/live-event observation here (the
  module-global AXObserver bridge can't host two adapters across a target-switch) — deferred to
  #14 (audit R3).

## Live-surface PROVE (real app launch; accessory, no focus; audio-cue wrapped)

Launched real `.build/debug/TermTile` with `TERMTILE_SELFTEST=1` (selftest suite pre-cleaned so
the pre-state is a genuine fresh `false`):

1. `PROCESS-ALIVE pid=3657` — the composition root built every real adapter
   (UserDefaultsSettingsStore / SMAppServiceLoginItem / WorkspaceTargetAppsProvider / live trust
   probe / AXWindowSystem-backed TilingActor) without crashing.
2. AX (read-only, System Events) — process "TermTile" **menu bar 2 → "status menu"**: the
   `MenuBarExtra` status item is registered with the window server and AX-enumerable.
3. CGWindowList — `TERMTILE-WINDOW id=80664 layer=25 bounds=[X:-4777,Y:0,W:72,H:37]`: layer 25 =
   `NSStatusWindowLevel`, a real status-bar item window. `X:-4777` = parked off-screen by this
   Mac's menu-bar manager (TRAP-1: environmental, not a defect — existence is proven by AX + the
   layer-25 window, never by pixels).
4. Selftest markers (UNBUFFERED stderr — TRAP-14: `print()` to a pipe is block-buffered and was
   lost on the first run's SIGTERM):
   ```
   SELFTEST start pid=3657 pre isEnabled=false
   SELFTEST persisted isEnabled=true target=dev.ecn.apps.termtile.selftest-none
   SELFTEST done
   ```
   The REAL `MenuBarViewModel.setEnabled(true)` executed in-process against the REAL
   `UserDefaultsSettingsStore`; a fresh cross-instance read shows the **false→true delta** (audit
   R5 — not a stale rubber-stamp). Target set to a NON-running bundle first, so `activate` was
   inert and **zero real windows moved** (the live tile is #14).

Cleanup: app terminated (no lingering process); selftest UserDefaults suite removed via
`defaults delete` (TRAP-4: no `rm -rf`); scratch files removed.

## Honest scope of this proof (audit R5)

Proven live: composition-root construction + real toggle→persist wire + shell status-item render.
**NOT** proven live (the single code-review-only residual): the SwiftUI `Button/Toggle → VM`
bindings in `MenuBarContent` (a `MenuBarExtra(.window)` popover can't be scripted without
clicking, and clicking is out of scope). Those bindings are trivial pass-throughs verified by
reading `MenuBarContent.swift`. The end-to-end click-to-tile flow is #14's fresh-boot E2E job.

## Deferred (real [DEP], not lazy)

- Live event observation (`TilingActor.run()`) + live grid tiling of the target app + the
  `visibleFrame` value's correctness against a real display → **#14** (needs real windows;
  un-provable in-process). [DEP: shape — live tiling needs real target windows] → #14
