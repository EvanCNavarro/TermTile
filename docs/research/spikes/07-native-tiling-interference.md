# Spike 07 — macOS Sequoia native tiling interference vs AX frame sets

**Task:** backlog `#7`. **blocked-by** `#4` (DONE).
**Environment:** macOS 15.1 (build 24B83), Swift 6, this Mac. Observed 2026-07-02.
**Code:** `Sources/TermTileCore/NativeTilingSettings.swift` (pure resolver, 8 tests),
`Sources/AXProbe/main.swift` `tilecheck` subcommand (live probe). Plan:
`.engine/state/stoke-plan-7.md`.

Answers the research doc's unverified area #3 (`docs/research/macos-tiling-research.md:80-82`):
"does native tiling fight AX-driven frame sets; per-app suppression?"

## The two questions, answered separately (audit R2)

### Q1 — Does native tiling FIGHT AX-driven (programmatic) frame sets?

**Auto/passive case: NO (observed).** macOS Sequoia native tiling is entirely
**user-gesture-initiated** — its three activation paths are drag-to-edge, drag-to-menu-bar,
and hold-Option-while-dragging (the toggle names + System Settings labels confirm this; see
the keys below). None fire on a programmatic `kAXPosition`/`kAXSize` write. This is
corroborated by **live evidence from spike-04**
(`docs/research/spikes/04-frame-writes.md`), which ran with these tiling keys **absent**
(= native drag-tiling ENABLED, the default) and still got a 5-frame battery of exact
readbacks, `<50ms` settle, and **zero reversion** — i.e. native tiling did not spontaneously
contest the frames. This spike adds NO new interference observation; it inherits spike-04's.

**Manual-tile case: UNVERIFIED (human-in-loop needed).** The one interference vector is: a
user *manually* native-tiles a window TermTile is managing — does that window then enter a
"tiled" state that RESISTS subsequent AX frame writes? Actuating a native tile requires
UI control (keyboard shortcut / green-button menu / drag-to-edge), which was declined in an
unattended autonomous beat; and there is **no read-only AX attribute** exposing tiled-group
membership, so it can't be observed passively. Recorded as an explicit UNVERIFIED for a
future human-in-loop run (same discipline as spike-04's cross-display clamp / spike-06's live
human-drag). Mitigation is already designed regardless: a user-driven tile is a window move
TermTile detects via the SAME drag-end signal as `#6` and re-tiles.

### Q2 — Per-app or global suppression options?

**Global suppression: YES, and programmatically controllable (PROVEN live).** The feature is
governed by four `com.apple.WindowManager` preference keys. The `tilecheck` probe exercised
the REAL `TermTileCore.NativeTilingSettings` resolver against the REAL domain and round-tripped
**all four** keys (write `false` → readback `false` → restore prior → readback prior):

| Key (`com.apple.WindowManager`)   | Meaning (Settings › Desktop & Dock)          | Default | Auto-snap path? | Round-trip |
|-----------------------------------|----------------------------------------------|---------|-----------------|------------|
| `EnableTilingByEdgeDrag`          | Drag windows to screen edges to tile         | enabled | yes             | ✅ writable+restored |
| `EnableTopTilingByEdgeDrag`       | Drag windows to menu bar to fill             | enabled | yes             | ✅ writable+restored |
| `EnableTilingOptionAccelerator`   | Hold Option while dragging to tile           | enabled | yes             | ✅ writable+restored |
| `EnableTiledWindowMargins`        | Tiled windows have margins (cosmetic)        | enabled | **no**          | ✅ writable+restored |

All four are ABSENT on a stock Sequoia install (= OS default = enabled), confirmed via
`defaults read` before AND after the probe (state fully restored, no leak). Setting
`EnableTilingByEdgeDrag=false` (etc.) is the documented global off-switch. **Whether
WindowServer live-honors the write without a relogin is a SECONDARY question, not tested**
(the probe proves the *surface is controllable*, which is the actionable finding).

**Per-app suppression: NO public API (audit A2, survived skeptic attack).** There is no
`NSWindow.collectionBehavior` flag, Info.plist key, or Spaces/CGS API that opts a window out
of user-initiated tiling. The ONLY effective exclusion is a **non-`.resizable`** window
(tiling resizes, so fixed-size/utility windows can't be tiled) — but that is a style-mask
property of the window, and **TermTile manages FOREIGN terminal windows whose style mask it
cannot set**. So there is no per-app lever available to TermTile.

## Implications for the build (#9/#10/#12)

- Native tiling will not spontaneously fight TermTile's layout writes (Q1 auto case).
- TermTile does NOT need to touch these prefs to function; but IF native drag-tiling ever
  proves disruptive during dogfooding, `#12`'s settings UX can offer an optional global
  "disable macOS edge-tiling" toggle by writing `EnableTilingByEdgeDrag=false` — the surface
  is proven controllable. Do NOT enable this by default (it mutates a system-wide user
  setting). `NativeTilingSettings` (Core) is ready to resolve the live state for such UX.
- Keep the manual-tile-resistance question on the `#14` E2E / human-in-loop checklist.

## Method / evidence (reproducible)

```
$ ./.build/debug/AXProbe tilecheck
tilecheck: macOS Version 15.1 (Build 24B83)
tilecheck: EnableTilingByEdgeDrag stored=absent resolved=true isAutoSnapPath=true
tilecheck: EnableTopTilingByEdgeDrag stored=absent resolved=true isAutoSnapPath=true
tilecheck: EnableTilingOptionAccelerator stored=absent resolved=true isAutoSnapPath=true
tilecheck: EnableTiledWindowMargins stored=absent resolved=true isAutoSnapPath=false
tilecheck: anyAutoSnapPathActive=true (REAL com.apple.WindowManager read)
tilecheck: roundtrip <each key> prior=absent afterSetFalse=false afterRestore=absent setOK=true restoreOK=true  (×4)
tilecheck: PASS=true   (exit 0)
```
- CFPreferences at `(kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` — exact scope
  `defaults`/`defaults write` touch (audit R5), NOT `CopyAppValue` (which merges
  NSGlobalDomain + both host layers and would misread a managed/byHost key).
- Restore is **INLINE before the single terminal `exit()`** + an `atexit` belt — **never
  `defer`**: a compiled probe confirmed `exit()` skips Swift `defer` (audit R1). Fixing this
  also repaired a pre-existing latent bug where `dragprobe`'s `defer`-restore of
  `AXEnhancedUserInterface` never ran. Enforced by `.engine/checks/axprobe-no-defer.sh`.

## Unknowns / caveats (honest)

- Manual-user-tile → subsequent-AX-write resistance: **UNVERIFIED** (needs human-in-loop; no
  passive AX signal for tiled-group membership).
- WindowServer live-honoring of the suppression write without relogin: **not tested**.
- Tahoe (macOS 26): keys may change; re-verify at build time (research doc caveat).
