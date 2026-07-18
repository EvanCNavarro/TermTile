# Decision 0004: Update Indicator Visibility Polish

## Status

Planned on 2026-07-18. Investigation complete. MacFaceKit Phase 1/2 implementation is complete and
published; TermTile Phases 3-6 are complete. Initial and final code-review findings against this plan
have been addressed in the sequencing below.

Current progress: Phases 0-6 complete, 100% total plan progress. MacFaceKit `v0.4.0`
(`5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`) is consumed by TermTile for shared indicator polish.

At the end of every implementation turn for this plan, report:

- Current phase and substep.
- Approximate total progress percentage.
- Validation run in that turn.
- Whether local nits, polish, flakes, or cleanup remain.
- Next steps, including whether more work is required.

Continuation rule: when resumed with `/order` and `/chug-02-continue`, re-run OBSERVE against the
real repo before BUILD and fix nits/polish/flakes as they are found.

## Context

The v0.2.6 update indicator works functionally, but the visible treatment needs polish:

- The overflow ellipsis dot renders, but it sits in the icon cluster and reads like another ellipsis dot.
- The menu-bar glyph screenshot does not show an orange indicator, even though the downgrade smoke proves
  Sparkle reports `UPDATE_PROBE_SMOKE available`.
- The dropdown row for "Check for Updates" does not show row-level attention, so the cause of the
  ellipsis attention is not visible once the menu opens.

Screenshot evidence from 2026-07-18:

- Menu-bar crop:
  `docs/verification/update-indicator-visibility/menu-bar-no-visible-dot-2026-07-18.png`, `160x134`,
  orange-family pixels `0`.
- Overflow button crop:
  `docs/verification/update-indicator-visibility/overflow-dot-current-placement-2026-07-18.png`,
  `186x134`, orange-family pixels `68`, bounding box `x=85...94`, `y=59...68`.
- Current orange-family predicate used only for screenshot evidence, not exact color matching:
  `r > 0.75 && g > 0.35 && g < 0.82 && b < 0.45 && r > g && g > b` in sRGB.
  Native screenshots can shift color through antialiasing, opacity, and display conversion, so future
  checks must combine thresholded pixel evidence with visual inspection.

## Verified Premises

- `TermTileApp` passes `updater.availability.hasAvailableUpdate` into `TermTileGlyph`.
- `MenuBarContent` passes the same availability source into the "Check for Updates" `MenuAction`.
- TermTile was pinned to MacFaceKit `0.3.3` before Phase 3.
- TermTile now consumes MacFaceKit `0.4.0`
  (`5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`) through normal SwiftPM resolution.
- Baseline MacFaceKit `0.3.3` used `AttentionDot` as the shared primitive with default `size: 5`,
  `color: Tokens.warning`.
- Baseline MacFaceKit `0.3.3` overlaid `IconButton` attention with `ZStack(alignment: .topTrailing)`.
- Baseline MacFaceKit `0.3.3` derived overflow button attention from `actions.contains { $0.attention }`.
- Baseline MacFaceKit `0.3.3` had no `MenuRow` attention input or trailing indicator.
- Baseline MacFaceKit `0.3.3` had only a generic `MenuAction.attention: Bool`; it did not carry an
  app-supplied accessibility semantic for why attention is requested.
- MacFaceKit `v0.4.0` now adds `Tokens.attentionDot`, bottom-right `IconButton` attention,
  row-level `MenuAction`/`MenuRow` attention, and caller-owned attention accessibility hints.

Every premise must be re-verified from code during the relevant OBSERVE step before BUILD.

## Brutal Audit

### Dependency Inversions To Avoid

- Do not hardcode a one-off ellipsis badge in TermTile when `IconButton` and `AttentionDot` are shared
  MacFaceKit primitives.
- Do not add a second update-available state; all indicators must still derive from
  `updater.availability.hasAvailableUpdate`.
- Do not hardcode TermTile-specific "update available" copy into MacFaceKit. MacFaceKit can expose a
  generic accessibility hook, but TermTile owns the concrete update semantic.
- Do not patch `.build/checkouts/MacFaceKit`; make changes in the real MacFaceKit repo, tag or otherwise
  consume them through normal dependency resolution.
- Do not make the menu-bar glyph depend on MacFaceKit if `MenuBarExtra` rendering requires app-specific
  image composition.

### Bundled Tasks To Split

- Shared dot size/color token.
- Icon-button attention placement.
- Dropdown-row attention placement.
- Menu-bar glyph rendering/positioning proof.
- TermTile dependency bump and wiring.
- Native visual verification and release documentation.

### Traps And Edge Cases

- `MenuBarExtra` may tint or template-label content, so a SwiftUI `Circle` can appear monochrome or vanish.
- A dot aligned inside an ellipsis icon can read as punctuation instead of state.
- Moving the dot outside a button can be clipped by the button label, popover, or menu-bar host.
- A larger dot can resize controls if the layout does not reserve stable dimensions.
- Row-level attention must stay decorative unless accessibility labels/hints expose the semantic state.
- Hover and active button states must keep enough contrast against `Tokens.rowActive`.
- Screenshot validation must use a tolerance/predicate and visual inspection; exact `Tokens.warning`
  pixel matching is too brittle for native antialiasing and display color conversion.

## Do Now

- No implementation work remains for this plan.
- Public release work is separate and requires an explicit release version/tag decision.

## Completed Upstream Work

- MacFaceKit `v0.4.0` fixes shared icon-button and dropdown-row indicator behavior.
- MacFaceKit `v0.4.0` adds a generic, optional attention accessibility semantic to rows/actions so hosts
  can explain the state without hardcoding app-specific copy in the shared kit.

## Depends On Future State

- Public release work is intentionally outside this polish plan until a release version is chosen.

## Continuation Audit: 2026-07-18

- Dependency inversion found: the original Phase 3 tried to use MacFaceKit's shared-size indicator before
  TermTile consumed the MacFaceKit release that defines it. The dependency bump must move before the
  TermTile shared-token implementation.
- Bundled task found: TermTile glyph placement, dropdown row semantics, dependency resolution, and live
  menu-bar proof were grouped too tightly. They are now separated into dependency readiness, app wiring,
  native proof, and documentation/review.
- Trap: a render test can prove SwiftUI composition, dimensions, and orange pixels, but it cannot prove
  `MenuBarExtra` host tinting. The native screenshot/pixel check remains a separate pitstop.
- Do-now split at audit time: bump to `v0.4.0`, add red-first source/render/accessibility tests, then
  implement the smallest TermTile wiring changes.
- Depends-on-future-state split at audit time: if native `MenuBarExtra` still hides or tints the colored
  dot after the shared SwiftUI implementation, then and only then add an app-specific precomposited
  status image path.

## Execution Plan

### Phase 0: Baseline And Visual Grounding

Status: Complete.

1. OBSERVE: inspect the provided screenshots and the installed downgrade-test app state.
2. OBSERVE: inspect `TermTileGlyph`, `MenuBarContent`, `AttentionDot`, `IconButton`, `OverflowMenu`, and
   `MenuRow`.
3. OBSERVE: pixel-check the supplied screenshots for orange indicator presence.
4. PITSTOP:
   - Look back: the overflow button has orange pixels but poor placement; the menu-bar crop has no orange
     pixels; the dropdown row lacks row attention by construction.
   - Look back: current architecture is modular, but the shared visual primitive is too weak.
   - Look forward: move shared control and row behavior into MacFaceKit before touching TermTile.

### Phase 1: MacFaceKit Attention Primitive And IconButton Placement

Status: Complete in MacFaceKit `v0.4.0` (`5e8eb0f`).

1. OBSERVE: inspect current MacFaceKit token and button tests.
2. RED: add a test requiring a single shared attention size/color authority.
3. RED: add a source/render invariant requiring `IconButton` attention to anchor bottom-trailing, not
   top-trailing.
4. BUILD: introduce the smallest shared attention metric, likely `Tokens.attentionDot`, and use
   `AttentionDot(size: Tokens.attentionDot)`.
5. BUILD: move `IconButton` attention to the lower-right button corner with stable button dimensions.
6. VERIFY: run MacFaceKit tests.
7. VERIFY: if MacFaceKit has an existing gallery or preview harness, render/screenshot the ellipsis button
   in inactive, hover, and open states; otherwise add the smallest deterministic harness needed before
   relying on screenshots.
8. PITSTOP:
   - Look back: verify the dot no longer reads as part of the ellipsis glyph.
   - Look back: fix sizing, offset, clipping, contrast, or hover-state polish before continuing.
   - Look forward: reuse the same primitive for menu rows.
   - Completed finding: `Tokens.attentionDot` is `7`, `AttentionDot` defaults to it, `IconButton`
     overlays the dot at bottom-trailing, and render tests prove the attended button does not resize.

### Phase 2: MacFaceKit Dropdown Row Attention

Status: Complete in MacFaceKit `v0.4.0` (`5e8eb0f`).

1. OBSERVE: inspect `MenuAction`, `OverflowMenu`, and `MenuRow` API compatibility.
2. RED: add a failing test for a generic app-supplied attention semantic on `MenuAction`, such as an
   optional `attentionAccessibilityValue` or `attentionAccessibilityHint`, with a compatibility default.
3. RED: add a failing test proving an attended `MenuAction` passes both `attention` and the semantic into
   `MenuRow`.
4. RED: add a failing render/source invariant proving `MenuRow(attention: true, ...)` renders a trailing
   shared `AttentionDot`.
5. RED: add a failing accessibility test proving the row exposes the app-supplied semantic without
   hardcoding update-specific copy in MacFaceKit.
6. BUILD: add `attention: Bool = false` plus the optional attention accessibility semantic to `MenuRow`.
7. BUILD: pass both values from `OverflowMenu` to `MenuRow`.
8. BUILD: keep the dot decorative and attach the semantic to the row accessibility label, value, or hint.
9. VERIFY: compile existing `MenuAction` call sites unchanged.
10. VERIFY: run MacFaceKit tests and render the dropdown with only "Check for Updates" attended.
11. PITSTOP:
   - Look back: verify row dot aligns at the trailing edge and does not crowd labels.
   - Look back: fix accessibility, truncation, spacing, and disabled/destructive combinations now.
   - Look forward: prepare a MacFaceKit version TermTile can consume, and record the exact tag/revision.
   - Completed finding: `MenuAction` and `MenuRow` carry defaulted attention state and caller-owned
     accessibility hints; `OverflowMenu` forwards the first attended action hint to the closed trigger and
     the row; render tests prove attended rows keep stable dimensions with trailing orange-family pixels.

### Phase 3: TermTile Dependency Readiness

Status: Complete.

1. OBSERVE: inspect `Package.swift`, `Package.resolved`, and the real MacFaceKit tag/revision state.
2. OBSERVE: identify the exact MacFaceKit tag/revision that contains bottom-trailing icon attention,
   dropdown-row attention, and the generic attention accessibility semantic. Assumption to verify: this
   will be newer than `0.3.3`.
   - Verified before this phase starts: MacFaceKit `v0.4.0`
     (`5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`) is newer than `0.3.3` and contains the required API.
3. RED: add or update a dependency/readiness test requiring that exact tag/revision or a concrete new API
   symbol from the MacFaceKit attention polish; do not let the existing `>= 0.3.3` check pass as proof.
4. BUILD: update MacFaceKit through normal dependency resolution.
5. VERIFY: run the dependency/readiness test.
6. PITSTOP:
   - Look back: verify no `.build/checkouts` patch, no duplicate dot primitive, and no second availability
     state.
   - Look back: fix dependency comments, stale docs, or package-resolution drift before continuing.
   - Look forward: proceed to TermTile app wiring only after `Tokens.attentionDot` and
     `attentionAccessibilityHint` compile from the real dependency.
   - Completed finding: TermTile now resolves MacFaceKit `0.4.0` at
     `5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`; readiness tests require `>= 0.4.0` and compile
     against `Tokens.attentionDot`.

### Phase 4: TermTile Glyph And Menu Wiring

Status: Complete.

1. OBSERVE: inspect `TermTileGlyph`, `MenuBarContent`, existing render tests, and source-invariant tests.
2. RED: add or strengthen render tests proving `TermTileGlyph(hasAvailableUpdate: true)` preserves stable
   dimensions and renders orange-family pixels in the lower-right quadrant.
3. RED: add a source/accessibility test proving the glyph exposes an update-available accessibility label
   and uses the shared MacFaceKit attention size instead of a local hardcoded dot size.
4. RED: add a TermTile menu test requiring the "Check for Updates" action to remain the single overflow
   attention source and to carry TermTile-owned accessibility semantics, such as "Update available."
5. BUILD: place the glyph indicator at bottom-trailing using a TermTile-owned original-color composited
   `NSImage` backed by MacFaceKit `Tokens.attentionDot` and `Tokens.warning`, because native
   `MenuBarExtra` evidence showed the SwiftUI overlay could render offscreen but disappear in the real
   menu-bar host.
6. BUILD: pass `attentionAccessibilityHint` from TermTile into the "Check for Updates" `MenuAction`.
7. VERIFY: run focused TermTile menu/glyph/release-readiness tests.
8. PITSTOP:
   - Look back: verify render size, lower-right orange pixels, source invariants, and menu semantics.
   - Look back: fix any layout, accessibility, stale-doc, or test-flake issues before native proof.
   - Look forward: proceed to native proof; do not add app-specific image composition unless the real
     menu-bar host evidence requires it.
   - Completed finding: the SwiftUI overlay rendered offscreen but did not survive `MenuBarExtra`; the
     final glyph uses a TermTile-owned original-color composited image and still sources attention size
     and color from MacFaceKit tokens.
   - Completed finding: the "Check for Updates" action supplies the TermTile-owned
     `attentionAccessibilityHint: "Update available"` and uses `Updater.canOpenUpdateCheck` so the row
     remains actionable once a passive probe finds an available update.

### Phase 5: Native Visual And Downgrade Smoke Verification

Status: Complete.

1. VERIFY: build and install an indicator-capable downgrade-test app with bundle version lower than the
   public appcast.
2. VERIFY: run `scripts/test-packaged-app.sh /Applications/TermTile.app`.
3. VERIFY: run `TERMTILE_UPDATE_PROBE_SMOKE=1` and require `armed`, `available`, `finished`.
4. VERIFY: capture native screenshots of:
   - menu-bar glyph resting with update available;
   - menu-bar glyph active/open with update available;
   - overflow button with update available;
   - dropdown row for "Check for Updates" with update available.
5. VERIFY: pixel-check screenshots for consistent orange-family presence using the documented predicate
   and inspect visually for placement, clipping, and readability.
6. PITSTOP:
   - Look back: fix any visual mismatch immediately.
   - Look forward: only docs/review/final gate remain.
   - Completed finding: `/Applications/TermTile.app` was installed as `0.2.5`/build `137` from current
     code using `TERMTILE_BUILD_NUMBER=137`, while the public appcast is `0.2.6`/build `138`.
   - Completed finding: packaged smoke passed and `TERMTILE_UPDATE_PROBE_SMOKE=1` reported `armed`,
     `available`, and `finished`.
   - Completed finding: final artifacts are recorded in
     `docs/verification/update-indicator-visibility/phase-5-native-proof.md`.

### Phase 6: Documentation, Review, And Final Gate

Status: Complete.

1. BUILD: update MacFaceKit README/DESIGN and TermTile verification docs with the final indicator
   behavior and screenshots.
2. VERIFY: run MacFaceKit tests.
3. VERIFY: run TermTile `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`.
4. REVIEW: run `superpowers:code-reviewer` against the MacFaceKit and TermTile diffs.
5. BUILD: fix every actionable finding before finalizing.
6. FINAL PITSTOP:
   - Look back: inspect final diffs, screenshots, tests, dependency files, and git status.
   - Look forward: identify only true future enhancements; do not defer polish required for this feature.
   - Completed finding: final review found no code-level issues after the active-session menu gate,
     release-CI override guard, and stale SwiftUI-overlay doc wording were fixed.
   - Completed finding: final TermTile gate passed with 267 tests and 0 SwiftLint violations.
   - Completed finding: packaged smoke passed against `/Applications/TermTile.app` installed as local
     downgrade proof `0.2.5`/build `137`.
   - Future enhancement: broaden visual proof across additional macOS appearance/menu-bar highlight
     combinations before the next public release if release scope allows.
