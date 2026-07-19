# Decision 0005: Live App Polish Before Release

## Status

Started on 2026-07-18 after local live-app testing of the update-indicator build.

Current progress: Phases 0-3 complete, 100% total plan progress.

Release boundary: this plan may commit and push source checkpoints, but it must not create a
TermTile public release tag or run the public release pipeline until the installed live app is tested
and release is explicitly approved.

## STOKE Audit

- Dependency inversion: the overflow ellipsis indicator is owned by MacFaceKit, not TermTile. Any
  corner change for icon controls must land upstream and be consumed through SwiftPM.
- Bundled task: live-app update-indicator polish, permission-card cleanup, and double-click
  zoom/restore behavior touch different owners. They are split into shared UI, TermTile UI wiring,
  and drag-classifier behavior.
- Trap: render tests can prove pixels and dimensions, but not every native menu-bar highlight state.
  A local installed-app screenshot remains required before release.
- Trap: resetting TCC rows and requesting permission in the same click can open both System Settings
  and the macOS permission prompt, leaving a stale dialog behind. The visible permission action should
  open Settings directly.
- Trap: System Settings can show TermTile as enabled while `AXIsProcessTrusted()` still returns false
  when the visible row belongs to an older signed copy. A settings-only link is insufficient for
  `grantBroken`; that state needs one explicit reset-and-open action.
- Trap: Input Monitoring can suffer the same stale `ListenEvent` row problem, but reset-only is wrong:
  the prompt-backed request path is what registers the current app in Settings. The visible notice must
  stay one action while resetting, re-registering, and opening Settings.
- Trap: old user-local app bundles can stay indexed by LaunchServices. Installer migration cleanup must
  remove both `~/Applications/TermTile` and `~/Applications/TermTile.app`.
- Trap: a title-bar double-click zoom/restore can change a window's frame without being a drag. Drag
  reorder must require a moved window whose size did not materially change.

## Do Now

- Add red-first tests for zoom/resize gestures, top-right indicator placement, and single permission
  actions.
- Add red-first tests for stale Accessibility recovery after live testing exposes a checked-but-untrusted
  app state.
- Implement focused fixes in the owning modules.
- Install a local candidate and verify the live app before any release decision.

## Depends On Future State

- Public `v0.2.7` or later release work depends on live-app test signoff and an explicit release
  instruction.

## Execution Plan

### Phase 0: Observe And Red Tests

Status: Complete.

1. OBSERVE: inspect TermTile and MacFaceKit ownership boundaries.
2. RED: prove resize/zoom gestures currently fire drag reorder.
3. RED: prove TermTile menu-bar glyph and MacFaceKit icon button still render attention in the old
   corner.
4. RED: prove current permission UI still exposes duplicate repair/open controls.
5. PITSTOP:
   - Look back: confirm failures match intended behavior, not unrelated build breakage.
   - Look forward: implement root fixes in `DragMonitor`, MacFaceKit `IconButton`/`NoticeCard`, and
     TermTile `MenuBarContent`/glyph wiring.

### Phase 1: Implement Root Fixes

Status: Complete.

1. BUILD: make `DragMonitor` ignore gestures where the candidate window's size changed.
2. BUILD: move MacFaceKit icon-button attention to the upper-right badge corner.
3. BUILD: render `NoticeCard` actions with the shared button-like link affordance.
4. BUILD: move TermTile's menu-bar composited update dot to the upper-right corner.
5. BUILD: collapse TermTile permission notices to one settings action per notice and remove duplicate
   visible repair buttons.
6. VERIFY: rerun the targeted red tests.
7. PITSTOP:
   - Look back: focused tests prove zoom/resize gestures do not fire drag-reorder, glyph pixels are
     upper-right, MacFaceKit icon-button pixels are upper-right, and permission notices expose one visible
     settings action.
   - Look back: `diff --check` is clean in both repos; no `.build/checkouts` files were edited.
   - Look forward: MacFaceKit changed, so publish/consume a patch library tag through SwiftPM before
     claiming TermTile has the shared UI fix.

### Phase 2: Dependency And Documentation

Status: Complete.

1. BUILD: if MacFaceKit changed, tag a patch library release and update TermTile through normal SwiftPM
   resolution.
   - Completed finding: MacFaceKit `v0.4.2`
     (`c430176469758fa465d2d3d9399859c9467bfd6e`) contains the shared upper-right icon attention,
     button-like `NoticeCard` links, and caller-owned notice actions.
   - Completed finding: TermTile now resolves MacFaceKit `0.4.2` through `Package.swift` and
     `Package.resolved`.
2. BUILD: update README, handoff, and verification docs to describe the live-test-only boundary and
   revised permission/indicator behavior.
   - Completed finding: `TERMTILE_GALLERY_UPDATE_AVAILABLE=1` is available only with `TERMTILE_GALLERY=1`
     and writes through `Updater.recordAvailableUpdate`, so native indicator screenshots no longer require
     installing a downgraded app.
3. VERIFY: run focused release-readiness and source-invariant tests.
   - Completed finding: focused drag, glyph, menu accessibility/render, AppKit source-invariant, and
     release-readiness tests pass.
4. PITSTOP:
   - Look back: ensure no `.build/checkouts` patch, no duplicated shared UI primitive, and no stale
     public-release claim.
   - Look forward: proceed to full validation only after docs and dependency files match reality.
   - Completed finding: MacFaceKit and TermTile diffs only touch owning modules, tests, package files, and
     durable docs; no checkout patch exists.

### Phase 2B: Stale Accessibility Recovery

Status: Complete.

1. OBSERVE: inspect the live-app screenshot and real `AccessibilityState.grantBroken` wiring.
   - Completed finding: the app was in `grantBroken`: `wasTrusted == true` locally while the current
     process still failed the Accessibility probe.
2. RED: prove `repairAccessibilityPermission()` resets only `.accessibility` and does not call any
   prompt-backed Accessibility trust request.
3. RED: prove `grantBroken` renders a single `Reset & Open Settings` action instead of a settings-only
   `Allow Accessibility` link.
4. BUILD: extend MacFaceKit `LinkButton`/`NoticeCard` so notice cards can reuse the same button styling
   for caller-owned actions.
5. BUILD: publish MacFaceKit `v0.4.2` and update TermTile's dependency floor/resolution through SwiftPM.
6. BUILD: wire TermTile's `grantBroken` notice to reset the stale TCC row, then open Accessibility
   Settings without spawning the extra macOS prompt dialog.
7. BUILD: wire the Input Monitoring notice to reset stale `ListenEvent` rows, re-register the current app,
   and open Settings through one visible action.
8. BUILD: fix installer migration cleanup for old `~/Applications/TermTile.app` copies.
9. VERIFY: rerun the focused VM, menu source-invariant, packaging, and release-readiness tests.
10. PITSTOP:
   - Look back: the live mismatch was a real stale-grant recovery gap, not an update-indicator issue.
     The focused tests now prove reset-without-prompt behavior for Accessibility, reset-and-register
     behavior for Input Monitoring, one visible action per notice, and cleanup of old user-local app
     bundle copies.
   - Look forward: full validation and native live proof must be repeated because the dependency graph and
     permission notice UI changed after the previous screenshots.

### Phase 3: Full Validation And Native Live Test

Status: Complete.

1. VERIFY: run MacFaceKit `swift build && swift test && swiftlint --strict`.
   - Completed finding: MacFaceKit `v0.4.2` passed `swift build`, `swift test` with 41 tests, and
     `swiftlint --strict` with 0 violations before tagging.
2. VERIFY: run TermTile `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`.
   - Completed finding: Sparkle fetch passed, `swift build` passed, `swift test` passed with 273 tests, and
     `swiftlint --strict` passed with 0 violations after the final installer invariant.
3. VERIFY: install a local downgrade/proof app and run `scripts/test-packaged-app.sh`.
   - Revised by grounded finding: do not install a downgraded app again. Install a current-code `0.2.7`
     local candidate and use `TERMTILE_GALLERY_UPDATE_AVAILABLE=1` for visual indicator proof.
   - Completed finding: `/Applications/TermTile.app` is installed as `0.2.7` build `146`, signed with
     `TermTile Dev Signing`, and packaged smoke passed with crash reports unchanged.
   - Completed finding: `scripts/install-app.sh` hit a live LaunchServices `-600` relaunch race. It now
     waits for the old process to exit and retries with `open -n`; `PackagingScriptsTests` pins this.
   - Completed finding: code review found `~/Applications/TermTile.app` was not cleaned up. The installer
     now removes both the `.app` bundle and legacy extensionless path before installing to `/Applications`.
4. VERIFY: capture native screenshots for top-right menu-bar, ellipsis, and simplified permission
   notices.
   - Completed finding: native screenshots and pixel checks are recorded in
     `docs/verification/live-app-polish-2026-07-18.md`.
   - Completed finding: the latest native screenshot shows the `grantBroken` notice with one
     `Reset & Open Settings` action and no duplicate lower repair button.
5. REVIEW: run `superpowers:code-reviewer` and fix every actionable finding.
   - Completed finding: final read-only code review found no actionable issues after the documentation
     truthfulness fixes and removal of the prompt-backed Accessibility ViewModel seam.
6. FINAL PITSTOP:
   - Look back: inspect code, tests, screenshots, docs, and git status from the real repo.
   - Completed finding: code, docs, screenshots, local install, packaged smoke, full gate, and reviewer
     result all match the implemented state.
   - Look forward: only after live-app user testing and explicit approval should public release work
     begin.
