# Decision 0004: Update Indicator Visibility Polish

## Status

Planned on 2026-07-18. Investigation complete. MacFaceKit Phase 1/2 implementation is complete and
published; TermTile app implementation has not started for this follow-up yet. Initial code-review
findings against this plan have been addressed in the sequencing below.

Current progress: Phases 0-2 complete, 40% total plan progress. MacFaceKit `v0.4.0`
(`5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`) is the consumer-ready shared indicator revision.

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
- TermTile is still pinned to MacFaceKit `0.3.3` until Phase 4.
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

- Prove whether the TermTile menu-bar label can render a colored dot, then choose the smallest
  TermTile-specific rendering fix only if required.
- Keep all TermTile app-surface indicators on MacFaceKit `Tokens.warning`/`Tokens.attentionDot` unless
  native menu-bar evidence proves host-specific sizing is needed.
- After menu-bar proof, bump TermTile to MacFaceKit `v0.4.0` and wire the "Check for Updates" action to
  the shared row/trigger attention accessibility hint without duplicating row UI.

## Completed Upstream Work

- MacFaceKit `v0.4.0` fixes shared icon-button and dropdown-row indicator behavior.
- MacFaceKit `v0.4.0` adds a generic, optional attention accessibility semantic to rows/actions so hosts
  can explain the state without hardcoding app-specific copy in the shared kit.

## Depends On Future State

- The final menu-bar implementation depends on a live screenshot/pixel check after trying a colored
  SwiftUI overlay in the real `MenuBarExtra`.
- The TermTile dependency update now has a real upstream target: MacFaceKit `v0.4.0`
  (`5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`).
- The dependency assertion in Phase 4 must target `v0.4.0` or a concrete new API symbol from that release
  rather than letting the currently sufficient `>= 0.3.3` check pass as proof.

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

### Phase 3: TermTile Menu-Bar Glyph Indicator Proof

1. OBSERVE: with the installed downgrade-test app, confirm `UPDATE_PROBE_SMOKE available` still occurs.
2. RED: add or strengthen render tests proving `TermTileGlyph(hasAvailableUpdate: true)` preserves stable
   dimensions and exposes an update-available accessibility label.
3. BUILD: first try a bottom-trailing shared-size `AttentionDot` in `TermTileGlyph`.
4. VERIFY: run a native menu-bar screenshot/pixel check looking for thresholded orange-family pixels, then
   visually inspect the crop for placement and clipping.
5. BUILD: if `MenuBarExtra` tints or clips the SwiftUI dot, switch to the smallest app-specific rendering
   route that preserves color, such as a precomposited original-color status image.
6. VERIFY: repeat native screenshot/pixel checks in resting and active menu-bar states using the documented
   threshold/predicate plus visual inspection.
7. PITSTOP:
   - Look back: verify the menu-bar dot is visible, orange, not clipped, and not confused with the glyph.
   - Look back: fix image/template behavior before proceeding.
   - Look forward: only then consume the MacFaceKit row/button polish.

### Phase 4: TermTile Dependency And Wiring

1. OBSERVE: inspect `Package.swift`, `Package.resolved`, and the real MacFaceKit tag/revision state.
2. OBSERVE: identify the exact MacFaceKit tag/revision that contains bottom-trailing icon attention,
   dropdown-row attention, and the generic attention accessibility semantic. Assumption to verify: this
   will be newer than `0.3.3`.
   - Verified before this phase starts: MacFaceKit `v0.4.0`
     (`5e8eb0fc6c3644dc0bc665e18a1a8a449cfbd981`) is newer than `0.3.3` and contains the required API.
3. RED: add or update a dependency/readiness test requiring that exact tag/revision or a concrete new API
   symbol from the MacFaceKit attention polish; do not let the existing `>= 0.3.3` check pass as proof.
4. RED: add a TermTile menu test requiring the "Check for Updates" action to remain the single overflow
   attention source and to carry TermTile-owned accessibility semantics, such as "Update available."
5. BUILD: update MacFaceKit through normal dependency resolution.
6. BUILD: use the new MacFaceKit row attention API without adding TermTile-specific duplicate row code.
7. VERIFY: run focused TermTile menu/glyph/release-readiness tests.
8. PITSTOP:
   - Look back: verify no `.build/checkouts` patch, no duplicate dot primitive, and no second availability
     state.
   - Look forward: proceed to native proof.

### Phase 5: Native Visual And Downgrade Smoke Verification

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

### Phase 6: Documentation, Review, And Final Gate

1. BUILD: update MacFaceKit README/DESIGN and TermTile verification docs with the final indicator
   behavior and screenshots.
2. VERIFY: run MacFaceKit tests.
3. VERIFY: run TermTile `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`.
4. REVIEW: run `superpowers:code-reviewer` against the MacFaceKit and TermTile diffs.
5. BUILD: fix every actionable finding before finalizing.
6. FINAL PITSTOP:
   - Look back: inspect final diffs, screenshots, tests, dependency files, and git status.
   - Look forward: identify only true future enhancements; do not defer polish required for this feature.
