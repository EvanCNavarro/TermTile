# Spike 03 — enumerate iTerm2 windows (task #3)

Observed on: Apple Swift 6.0.3, macOS 15.1 (24B83), arm64; iTerm2 running (pid 12953),
15 pre-existing windows. Probe: `Sources/AXProbe/main.swift` `enumerate <bundle-id>` mode
(throwaway-quality, committed per Phase A contract); durable tested code:
`Sources/TermTile/WindowFiltering.swift`. Baseline read-only observations were first made
by the stoke-plan-3 audit agent and reproduced identically by the committed probe.

## Questions → observed answers

### 1. Do native tabs present as one AXWindow? → YES, one.
Created one window, added 2 tabs (AppleScript confirms `count of tabs` = 3). AX window
count went 15 → exactly 16; the single new AXWindow (id 78051) covered all three tabs.
Tabs are an in-window tab bar, invisible to `kAXWindowsAttribute`. **Layout math (#8)
counts windows, not tabs.**

### 2. Window IDs via `_AXUIElementGetWindow`? → works, and it's a THREE-way join.
The declaration that compiles/links under Swift 6 with zero extra flags:

```swift
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError
```

Returned `.success` for every window in every probe run; ids matched
`kCGWindowNumber` in `CGWindowListCopyWindowInfo` 15/15, 16/16, 17/17 across the three
states. Bonus (audit F5, confirmed live): **iTerm2's AppleScript window `id` IS the same
CGWindowID** (78051/78056 identical across AppleScript ↔ AX ↔ CGWindowList) — spike/E2E
tooling can address windows deterministically. Rectangle's frame-equality fallback was
never needed; keep it as contingency for other apps.

### 3. Minimized / fullscreen / subrole filtering?
- **Minimized windows STAY in `kAXWindows`** with `kAXMinimized=true` (err 0) AND retain
  real, non-degenerate frames (10 of 15 baseline windows were minimized, e.g.
  `min=true frame=(538,46 1081x1002)`). Filtering must be attribute-based, never
  absence-based; a cached frame of a minimized window is still meaningful (#8/#9).
- **`AXFullScreen` is readable** (err 0, `false` on all windows). UNVERIFIED edge:
  enumeration behavior *while* a window is fullscreen (own Space) — deferred to #7
  [DEP: shape — fullscreen behavior is #7's native-tiling surface].
- **Subrole:** every iTerm2 window observed is `role=AXWindow subrole=AXStandardWindow`.
  UNVERIFIED: hotkey-window subrole (none configured on this Mac); the
  `WindowFiltering.isTileable` predicate is fail-closed (nil/non-standard → not tileable),
  so an exotic subrole is excluded by default.

## CGWindowList cross-check — join by id, NEVER compare counts
`CGWindowListCopyWindowInfo(.optionAll)` pid-filtered = 22 entries vs AX 15: iTerm2 owns
4 unnamed phantom layer-0 windows (1728×37, y=0), layer-3 panels (NSColorPanel etc.), and
a layer-103 overlay — none reported by AX. Reconstructing the tileable set from CG data
requires layer==0 AND id-membership-in-AX. The probe prints `ax-ids-in-cg=N/N` as the
match check.

## Environment facts probes can rely on (observed)
- This dev shell inherits Accessibility trust through the terminal chain (even via tmux);
  `trusted=true`, no per-binary grant (spike 02 mechanism re-confirmed).
- Automation (AppleEvents) grant iTerm2→iTerm2-chain pre-exists (`kTCCServiceAppleEvents
  … auth=2`): `osascript` against iTerm2 works promptless from this context.
- iTerm2 AppleScript dialect: `first window whose id is N` FAILS (-1719 Invalid index);
  use the direct element form `window id N`. Window ordering ≠ z-order (window 1 can be
  a minimized window) — always address by id.
- AeroSpace.app is installed (Accessibility-granted, currently not running). If launched
  it would fight TermTile for the same windows — flag for #9+ docs.

## UNVERIFIED edges (explicit)
- `kAXWindows` completeness across Spaces: no iTerm2 window lived on another Space during
  probing; the well-known omits-other-Spaces limitation could not be confirmed/denied.
  #9's state model must NOT assume kAXWindows is Space-complete.
- Fullscreen-state enumeration + hotkey-window subrole (above).

## Anomaly log (honest record)
During cleanup the two spike-created windows (78051, 78056) disappeared before the
scripted close ran (its first statement failed on the `whose` dialect issue, so the
script closed nothing) — externally closed, most plausibly by the user after the audio
cue. Post-state was verified identical to baseline three ways (AppleScript id list, AX
count 15 with 15/15 CG id-join, CG pid-window count 22). No pre-existing window was
touched at any point.

## Consequences for the build
- #8: layout input = count of tileable AXWindows (tabs collapse; minimized excluded by
  predicate, not by absence).
- #9: cache keyed by CGWindowID from `_AXUIElementGetWindow`; keep frame-equality
  fallback; treat Space-completeness as unknown; filtering via `WindowFiltering.isTileable`
  (fail-closed optionals).
- #4 (next): frame WRITES on these same enumerated windows — size→position→size,
  AXEnhancedUserInterface off; the enumerate machinery here is its starting point.
