# TermTile - Handoff

_Last updated: 2026-07-18. This is the single spot to pick TermTile back up. Read it top-to-bottom,
then jump to **Start here**. (Companion handoffs: `RememBar/HANDOFF.md`, `MacFaceKit/README.md` -
the three repos share the MacFaceKit design system.)_

## Current state

| Check | State |
|---|---|
| Build | Run `swift build` before claiming health |
| Tests | Run `swift test` before claiming health |
| Lint | Run `swiftlint --strict` before claiming health |
| Git | Check `git status --short` before release |
| Latest published release | **v0.2.5** (2026-07-18), build 134, Developer ID signed/notarized/stapled |
| Release target | None active; next version TBD |
| Latest unreleased work | None; Task #36 optional `Bring app forward` behavior shipped in v0.2.5 |
| Public signing | Developer ID Application: Evan Navarro (`XG9SBNWNXT`) |
| Notarization | Accepted; release CI notarizes, staples, and Gatekeeper-assesses before zipping |
| Design-system dep | MacFaceKit `.upToNextMinor(from: "0.3.2")` (public git URL, auto-resolved) |

## Start here (next session, in order)

1. **Sanity-check health** - `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`.
   If the build reds with "invalid redeclaration", check for stray `* 2.swift` Finder/Xcode duplicate
   files (`find Sources Tests -name '* 2.swift'`) and delete them; the tracked originals are truth.
   (This bit RememBar this session; TermTile is currently clean.)
2. **Verify notarized release artifacts after the next public release.** Use `docs/NOTARIZATION.md`:
   fresh-download the zip, verify checksum/provenance, then run `codesign`, `stapler validate`, and
   `spctl --assess` against the downloaded `TermTile.app`. This was completed for `v0.2.5`.
3. **Pick up product work** from the backlog. TermTile does one thing (tile a chosen app's windows into
   an even grid); the open arcs are polish + reach: onboarding/first-run guidance, more target apps,
   smoother tiling. Check `.engine/BACKLOG.md` + `.engine/state/` (STOKE plans) for the tracked queue.

## Where the project is

- **Latest release:** v0.2.5 - menu-bar window-tiler: pick a terminal (iTerm2/WezTerm), press
  **Rearrange now**, and windows snap into even columns of two. The Rearrange section now has a
  default-off **Bring app forward** option that asks macOS to focus the selected target app after
  tiling. It is Developer ID signed, notarized, stapled, Gatekeeper-assessed by release CI, and
  published with a signed Sparkle appcast. It keeps the v0.2.4 uninstall privacy cleanup and stale
  permission repair flows. `v0.2.1` was the transitional signed but unstapled build used to stabilize
  macOS TCC grants across updates.
- **Released in v0.2.0:** the richer identity card, GitHub/License links,
  adjustable gap, configurable shortcut, drag-reorder controls, Uninstall, clearer Accessibility/Input
  Monitoring guidance, branded update dialog, and stricter release-readiness tests.
- **The big recent UI arc:** adopted the shared **MacFaceKit** design system
  (`github.com/400faces/MacFaceKit`, public, pinned `.upToNextMinor(from: "0.3.2")`). TermTile is now a
  UI-twin of RememBar: same identity card, icon buttons, and **branded update dialog** (via
  `TermTileUserDriver`, a thin Sparkle→`UpdateWindowController` adapter; the window/morph/model live once
  in the kit). The Rearrange-now hero uses the shared `PrimaryButton` (left-aligned this session).
- **Architecture (ADR-0001, functional core / imperative shell):** `TermTileCore` = pure layout math +
  domain types (CoreGraphics only, no AppKit; enforced by `.engine/checks/core-purity.sh`). `TermTileKit`
  = the Accessibility/window-system port (`AXWindowSystem`, `TilingActor`). `TermTile` = the thin SwiftUI
  menu-bar shell (`MenuBarContent`, `MenuBarViewModel`, `Updater`, `TermTileApp` composition root).
- **Update flow:** `Updater` (lazy-starts Sparkle on first check — NOT at launch, so no first-run
  permission prompt steals focus on this `.accessory` app) → `TermTileUserDriver` → `MacFaceKit.UpdateWindowController`.

## Known-good dev hooks / gotchas

- `TERMTILE_GALLERY=1` — opens the real `MenuBarContent` panel in a window (visual review).
- `TERMTILE_AUTOCHECK=1` — fires an update check on launch (drives the branded dialog end-to-end without
  the menu). `TERMTILE_STOCK_UPDATER=1` — rollback to Sparkle's stock UI.
- `TERMTILE_TILE_ONCE=1` — one-shot tile against the persisted target (demo/E2E).
- Sparkle is a **vendored `Vendor/Sparkle.xcframework`** (gitignored) - run `scripts/fetch-sparkle.sh`
  once after clone, and again if a build reds with "no such module 'Sparkle'". `build-app.sh` embeds it
  last; an interrupted build yields an app that dyld-aborts on `@rpath/Sparkle.framework`; re-run it whole.
- `.engine/state/*.md` (STOKE plan files) are gitignored working notes; local-only, don't expect them in git.

## Open items / deferred

- **Post-release artifact verification** - completed for `v0.2.5`: checksum, codesign, stapler,
  Gatekeeper, bundle metadata, latest appcast, release workflow, and `gh attestation verify
  TermTile-v0.2.5.zip --repo EvanCNavarro/TermTile`. Evidence:
  `docs/verification/release-v0.2.5.md`.
- `[DEP:#33]` — RememBar's `ProcessRunner` 1s drainer-wait ceiling (shared-pattern note; RememBar's concern,
  low risk). Tracked in that repo.
- Twin-drift with RememBar is intentional + documented: TermTile's `Updater` is a lazy instance gated by
  `canCheckForUpdates`; RememBar's is a global singleton. TermTile's is the cleaner pattern — don't "fix"
  into false symmetry.
