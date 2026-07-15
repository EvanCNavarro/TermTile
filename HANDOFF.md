# TermTile — Handoff

_Last updated: 2026-07-15. This is the single spot to pick TermTile back up. Read it top-to-bottom,
then jump to **▶ Start here**. (Companion handoffs: `RememBar/HANDOFF.md`, `MacFaceKit/README.md` —
the three repos share the MacFaceKit design system.)_

## Current state (all green)

| Check | State |
|---|---|
| Build | ✅ `swift build` — clean |
| Tests | ✅ `swift test` — **166 passing** |
| Lint | ✅ `swiftlint --strict` — **0 violations** |
| Git | Check `git status --short` before release; release-readiness edits may be uncommitted locally |
| Latest release | **v0.1.0** (2026-07-03) |
| Unreleased on `master` | user-facing work ready (branded update dialog, redesigned About, hero button) — a **v0.2.0** is warranted, see ▶ Start here |
| Design-system dep | MacFaceKit `.upToNextMinor(from: "0.3.2")` (public git URL, auto-resolved) |

## ▶ Start here (next session, in order)

1. **Sanity-check health** — `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict` (expect 166 pass).
   If the build reds with "invalid redeclaration", check for stray `* 2.swift` Finder/Xcode duplicate
   files (`find Sources Tests -name '* 2.swift'`) and delete them — the tracked originals are truth.
   (This bit RememBar this session; TermTile is currently clean.)
2. **Decide: cut v0.2.0.** `master` is well ahead of v0.1.0 with user-facing work — the shared **branded
   update dialog** (same as RememBar, was Sparkle's stock alert), the **redesigned About/identity card**
   (icon, version, GitHub + License links, the "tidy, even grid" subtitle), and the **left-aligned
   Rearrange-now hero button**. A draft `release-notes/0.2.0.md` is already written — review/expand it,
   then `git tag v0.2.0 && git push origin v0.2.0` (**tagging is GATED — it publishes a public Release
   via `.github/workflows/release.yml`; confirm before pushing the tag**). Release process: `docs/RELEASING.md`.
3. **Pick up product work** from the backlog. TermTile does one thing (tile a chosen app's windows into
   an even grid); the open arcs are polish + reach: onboarding/first-run guidance, more target apps,
   smoother tiling. Check `.engine/BACKLOG.md` + `.engine/state/` (STOKE plans) for the tracked queue.

## Where the project is

- **Released & live:** v0.1.0 — menu-bar window-tiler: pick a terminal (iTerm2/WezTerm), press
  **Rearrange now**, and windows snap into even columns of two. The public release has the simpler
  menu from tag `v0.1.0` (target picker, launch-at-login, Accessibility fix-it, Check for Updates,
  Quit).
- **Ready for v0.2.0:** the current `master` adds the richer identity card, GitHub/License links,
  adjustable gap, configurable shortcut, drag-reorder controls, Uninstall, clearer Accessibility/Input
  Monitoring guidance, branded update dialog, and stricter release-readiness tests.
- **The big recent arc (this session):** adopted the shared **MacFaceKit** design system
  (`github.com/400faces/MacFaceKit`, public, pinned `.upToNextMinor(from: "0.3.2")`). TermTile is now a
  UI-twin of RememBar — same identity card, icon buttons, and **branded update dialog** (via
  `TermTileUserDriver`, a thin Sparkle→`UpdateWindowController` adapter; the window/morph/model live once
  in the kit). The Rearrange-now hero uses the shared `PrimaryButton` (left-aligned this session).
- **Architecture (ADR-0001, functional core / imperative shell):** `TermTileCore` = pure layout math +
  domain types (CoreGraphics only, no AppKit — enforced by `.engine/checks/core-purity.sh`). `TermTileKit`
  = the Accessibility/window-system port (`AXWindowSystem`, `TilingActor`). `TermTile` = the thin SwiftUI
  menu-bar shell (`MenuBarContent`, `MenuBarViewModel`, `Updater`, `TermTileApp` composition root).
- **Update flow:** `Updater` (lazy-starts Sparkle on first check — NOT at launch, so no first-run
  permission prompt steals focus on this `.accessory` app) → `TermTileUserDriver` → `MacFaceKit.UpdateWindowController`.

## Known-good dev hooks / gotchas

- `TERMTILE_GALLERY=1` — opens the real `MenuBarContent` panel in a window (visual review).
- `TERMTILE_AUTOCHECK=1` — fires an update check on launch (drives the branded dialog end-to-end without
  the menu). `TERMTILE_STOCK_UPDATER=1` — rollback to Sparkle's stock UI.
- `TERMTILE_TILE_ONCE=1` — one-shot tile against the persisted target (demo/E2E).
- Sparkle is a **vendored `Vendor/Sparkle.xcframework`** (gitignored) — run `scripts/fetch-sparkle.sh`
  once after clone, and again if a build reds with "no such module 'Sparkle'". `build-app.sh` embeds it
  LAST — an interrupted build yields an app that dyld-aborts on `@rpath/Sparkle.framework`; re-run it whole.
- `.engine/state/*.md` (STOKE plan files) are gitignored working notes — local-only, don't expect them in git.

## Open items / deferred

- **v0.2.0 release** — ready, gated on your decision (see ▶ 2).
- `[DEP:#33]` — RememBar's `ProcessRunner` 1s drainer-wait ceiling (shared-pattern note; RememBar's concern,
  low risk). Tracked in that repo.
- Twin-drift with RememBar is intentional + documented: TermTile's `Updater` is a lazy instance gated by
  `canCheckForUpdates`; RememBar's is a global singleton. TermTile's is the cleaner pattern — don't "fix"
  into false symmetry.
