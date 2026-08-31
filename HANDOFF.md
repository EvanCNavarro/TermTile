# TermTile - Handoff

_Last updated: 2026-08-31. This is the single spot to pick TermTile back up. Read it top-to-bottom,
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
| Latest unreleased work | **Session tint (ADR 0006, Phase F)** — colours each terminal session by what its agent is doing. Complete and live-verified, OFF by default, NOT yet released. Plus earlier live-app polish: top-right update indicators, stale-permission recovery, zoom-safe drag-reorder. |
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

## Session tint (ADR 0006) — the newest feature, and the one with the most context

Colours each target session by agent state: green idle, amber blocked on you, normal working.
**Off by default**, and it needs no permission beyond the Accessibility grant tiling already uses.

Read `docs/decisions/0006-session-state-tinting.md` before touching it. Nine findings there were
measured, several of them after a wrong first answer, and the ADR keeps the corrections visible
rather than rewriting history.

**The four that will bite you if you skip them:**

- **Pane index is a CREATION counter, not a position** (finding 6b). Geometry cannot recover it. An
  earlier two-pane observation looked like row-major only because the panes were created
  left-then-right; a 2x2 grid built right-before-left disproved it.
- **`shift+tab to cycle` is NOT an idle marker** (finding 8). It was measured on a window actively
  running a command. Using it turns a working window green, which invites interrupting live work.
- **iTerm's AX text carries `U+0000` where padding sits** (finding 7b), so every marker containing a
  space matched only intermittently. Normalise before matching.
- **Ready requires a MEASURED character-count delta** (finding 9), and the delta can go NEGATIVE as
  scrollback re-renders — the test is `!= 0`, never `> 0`.

**Proving it:** `TT_LIVE_AX=1 swift test --filter Live` runs every live test; they skip without the
env var so CI stays hermetic. `TT_LIVE_AX=1 TT_LIVE_WRITE=1` additionally paints real terminals.
Rendered UI evidence and the full method are in `docs/verification/session-tinting-2026-08-31.md`.

**Testing the debug binary?** `.build/debug/TermTile` has no `Info.plist`, so `UserDefaults.standard`
resolves to the **`TermTile`** domain, not `dev.ecn.apps.termtile`. Seeding the bundle-id domain and
launching the debug binary proves nothing — it reads absent keys and correctly does nothing, which
is indistinguishable from broken wiring. This cost a confident wrong conclusion once already.

**What remains:** backlog `#37g` retires the out-of-tree poller this replaces, and is deliberately
gated on daily use rather than on a green suite. Its source is preserved at
`docs/reference/replaced-tooling/` so the removal is recoverable. Open issues:
EvanCNavarro/TermTile#6 (widen the blocked-marker vocabulary), #12 (Tier 2 Apple Events — stronger
now than when deferred, since the session-name glyph is unreadable on renamed windows), #13 (verify
the OSC write path against WezTerm before any multi-terminal claim).

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
