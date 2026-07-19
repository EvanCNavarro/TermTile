# TermTile - Handoff

_Last updated: 2026-07-19. This is the single spot to pick TermTile back up. Read it top-to-bottom,
then jump to **Start here**. (Companion handoffs: `RememBar/HANDOFF.md`, `MacFaceKit/README.md` -
the three repos share the MacFaceKit design system.)_

## Current state

| Check | State |
|---|---|
| Build | Run `swift build` before claiming health |
| Tests | Run `swift test` before claiming health |
| Lint | Run `swiftlint --strict` before claiming health |
| Git | Check `git status --short` before release |
| Latest published release | **v0.2.6** (2026-07-18), build 138, Developer ID signed/notarized/stapled |
| Release target | None active; v0.2.6 is published |
| Latest unreleased work | Live-app polish after v0.2.6: top-right update indicators, stale-permission recovery, and zoom-safe drag-reorder. |
| Public signing | Developer ID Application: Evan Navarro (`XG9SBNWNXT`) |
| Notarization | Accepted; release CI notarizes, staples, and Gatekeeper-assesses before zipping |
| Design-system dep | MacFaceKit `.upToNextMinor(from: "0.4.2")` (public git URL, auto-resolved) |

## Start here (next session, in order)

1. **Sanity-check health** - `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`.
   If the build reds with "invalid redeclaration", check for stray `* 2.swift` Finder/Xcode duplicate
   files (`find Sources Tests -name '* 2.swift'`) and delete them; the tracked originals are truth.
   (This bit RememBar this session; TermTile is currently clean.)
2. **Verify notarized release artifacts after each public release.** Use `docs/NOTARIZATION.md`:
   fresh-download the zip, verify checksum/provenance, then run `codesign`, `stapler validate`, and
   `spctl --assess` against the downloaded `TermTile.app`. This was completed for `v0.2.6`;
   evidence is in `docs/verification/release-v0.2.6.md`.
3. **For the next release, repeat the tag workflow.** Author `release-notes/<version>.md`, run the
   local gate, commit the complete release diff, create `v<version>`, and push `master` + the tag.

## Where the project is

- **Latest release:** v0.2.6 - menu-bar window-tiler: pick a terminal (iTerm2/WezTerm), press
  **Rearrange now**, and windows snap into even columns of two. The Rearrange section now has a
  default-off **Bring app forward** option that asks macOS to focus the selected target app after
  tiling. v0.2.6 adds Sparkle-backed update indicators in the menu-bar glyph and overflow menu, and
  tightens drag-reorder so content/screenshot drags inside an unchanged focused window do not snap it
  back to the grid. It is Developer ID signed, notarized, stapled, Gatekeeper-assessed by release CI,
  and published with a signed Sparkle appcast. It keeps the v0.2.4 uninstall privacy cleanup and stale
  permission repair flows. `v0.2.1` was the transitional signed but unstapled build used to stabilize
  macOS TCC grants across updates.
- **Unreleased live-app polish:** top-right update dots on the menu-bar glyph and overflow ellipsis,
  row-level **Check for Updates** attention, a **Reset & Open Settings** stale-Accessibility recovery
  action, button-like permission notice actions, and drag-reorder ignoring title-bar zoom/resize gestures.
  MacFaceKit v0.4.2 is consumed for the shared UI pieces.
- **Released in v0.2.0:** the richer identity card, GitHub/License links,
  adjustable gap, configurable shortcut, drag-reorder controls, Uninstall, clearer Accessibility/Input
  Monitoring guidance, branded update dialog, and stricter release-readiness tests.
- **The big recent UI arc:** adopted the shared **MacFaceKit** design system
  (`github.com/400faces/MacFaceKit`, public, pinned `.upToNextMinor(from: "0.4.2")`). TermTile is now a
  UI-twin of RememBar: same identity card, icon buttons, shared attention indicator, and **branded update
  dialog** (via `TermTileUserDriver`, a thin Sparkle→`UpdateWindowController` adapter; the
  window/morph/model live once in the kit). The Rearrange-now hero uses the shared `PrimaryButton`.
- **Architecture (ADR-0001, functional core / imperative shell):** `TermTileCore` = pure layout math +
  domain types (CoreGraphics only, no AppKit; enforced by `.engine/checks/core-purity.sh`). `TermTileKit`
  = the Accessibility/window-system port (`AXWindowSystem`, `TilingActor`). `TermTile` = the thin SwiftUI
  menu-bar shell (`MenuBarContent`, `MenuBarViewModel`, `Updater`, `TermTileApp` composition root).
- **Update flow:** `Updater` owns Sparkle in the executable target. On normal launch it starts one
  passive `checkForUpdateInformation()` probe for update-available indicators; **Check for Updates…**
  still opens the foreground Sparkle update flow through `TermTileUserDriver` and
  `MacFaceKit.UpdateWindowController`.

## Known-good dev hooks / gotchas

- `TERMTILE_GALLERY=1` — opens the real `MenuBarContent` panel in a window (visual review).
- `TERMTILE_GALLERY_UPDATE_AVAILABLE=1` with `TERMTILE_GALLERY=1` — marks the single `Updater`
  availability source as available for native indicator screenshots without downgrading the app.
- `TERMTILE_AUTOCHECK=1` — fires an update check on launch (drives the branded dialog end-to-end without
  the menu). `TERMTILE_STOCK_UPDATER=1` — rollback to Sparkle's stock UI.
- `TERMTILE_TILE_ONCE=1` — one-shot tile against the persisted target (demo/E2E).
- Sparkle is a **vendored `Vendor/Sparkle.xcframework`** (gitignored) - run `scripts/fetch-sparkle.sh`
  once after clone, and again if a build reds with "no such module 'Sparkle'". `build-app.sh` embeds it
  last; an interrupted build yields an app that dyld-aborts on `@rpath/Sparkle.framework`; re-run it whole.
- `.engine/state/*.md` (STOKE plan files) are gitignored working notes; local-only, don't expect them in git.

## Open items / deferred

- **Post-release artifact verification** - recurring release task; latest completed for `v0.2.6`:
  checksum, codesign, stapler, Gatekeeper, bundle metadata, latest appcast, release workflow, and
  `gh attestation verify TermTile-v0.2.6.zip --repo EvanCNavarro/TermTile`. Evidence:
  `docs/verification/release-v0.2.6.md`.
- `[DEP:#33]` — RememBar's `ProcessRunner` 1s drainer-wait ceiling (shared-pattern note; RememBar's concern,
  low risk). Tracked in that repo.
- Twin-drift with RememBar is intentional + documented: TermTile's `Updater` is a lazy instance gated by
  `canCheckForUpdates`; RememBar's is a global singleton. TermTile's is the cleaner pattern — don't "fix"
  into false symmetry.
