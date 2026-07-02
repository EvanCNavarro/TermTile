# TermTile — Spec Draft (provisional, not final)

Status: draft from /project-start intake, 2026-07-02. Decisions below are recommended
defaults, not locked scope. Research authority: `docs/research/macos-tiling-research.md`.

## Problem

Bobby runs many terminal windows (iTerm2 today, WezTerm previously) and hand-arranges
them into an even grid for visibility. No macOS tiler does per-app-scoped, fixed
2-rows-per-column auto-tiling out of the box (verified: Amethyst/yabai/AeroSpace layout
catalogs enumerated).

## Product shape (v1)

- Swift 6 SPM **menu-bar app** (RememBar template: SwiftUI, bundled .app, scripts for
  build/package/smoke-test; Sparkle deferred until it earns its keep).
- **Toggle on/off** from the menu bar. Off = no rigid behavior at all.
- **Target app picker** (default iTerm2; any running app selectable — must work for
  WezTerm too).
- **Layout algorithm**: N visible standard windows of the target app on the active
  display → `columns = ceil(N / 2)`, each column holds 2 windows (last column holds 1 if
  N is odd), all columns equal width, rows split the visible frame height evenly.
- **Auto-retile** on window created/destroyed/miniaturized (AXObserver per-pid +
  NSWorkspace launch/terminate).
- **Drag snap-reorder**: user drags a window; on drag end, the dragged window takes the
  slot whose center is nearest the drop point; remaining windows shuffle to fill;
  instant frame sets (no animation in v1 — compositor animation requires SIP-level
  injection, out of scope by decision).

## Architecture decisions (from verified research)

1. Public Accessibility API only; Accessibility TCC permission; never SIP. [AeroSpace/Amethyst model]
2. Per-app AXObserver (system-wide element does not support notifications).
3. Rectangle's pitfall workarounds: size→position→size for cross-display, disable
   `AXEnhancedUserInterface` before resize, `_AXUIElementGetWindow` + frame-match fallback.
4. Swindler *pattern* (not dependency): cached window-state model, async writes, tag
   self-initiated moves (`external` flag) so retiles don't recurse.
5. Reduced AX messaging timeout (~1s, alt-tab-macos precedent) so a hung app can't stall the tiler.

## MVP cut-line

In: single display (active display), toggle, app picker, 2-per-column layout, auto-retile,
drag snap-reorder, launch-at-login.
Out (v1): multi-display spanning, Spaces awareness, animations, per-app profiles,
gap/padding settings UI (hardcode sane gaps), Sparkle updates.

## Open questions (resolve by spike, in order)

1. iTerm2 AX behavior: tabs-as-one-window? min sizes? prompt `kAXPosition` honor? → Spike 1.
2. Drag-end detection: global mouse-up (CGEventTap) vs debounced kAXMoved → read
   Rectangle/Amethyst source, then spike.
3. Sequoia native tiling interference with AX frame sets → test on this Mac's OS.
4. Swift 6 strict concurrency vs CFRunLoop AXObserver callbacks → likely dedicated
   run-loop thread wrapper.

## Known scaffold mismatches (accepted, cleanup later)

- Lab baseline is web-oriented: `package.json` command contract and Cloudflare deploy
  intent don't apply to a Swift app. Keep contract files; replace command surface with
  `swift build/test` + scripts/ once the SPM package lands.
