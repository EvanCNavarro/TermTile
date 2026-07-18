# Decision 0003: Update Availability Indicators

## Status

Implemented locally in focused phases on 2026-07-18 and released publicly as TermTile v0.2.6.

Current progress: Phase 10 complete, 100% local implementation complete, and public release complete.
The v0.2.6 release pipeline published the signed/notarized zip, checksum, provenance attestation,
release notes, and Sparkle appcast.

Final validated outcomes:

- Sparkle update availability is observed through the executable-target `Updater`.
- TermTile does not parse appcasts, GitHub releases, XML, or raw update URLs.
- The menu-bar glyph and overflow ellipsis derive attention from one availability source.
- MacFaceKit owns the reusable attention dot and overflow attention API.
- Drag-reorder now requires a real candidate-window frame change, so terminal text selection and
  screenshot-region drags inside an unchanged focused/maximized window do not trigger a grid snap.
- `swift build && swift test && swiftlint --strict` passed with 257 tests and 0 lint violations.
- `scripts/test-packaged-app.sh dist/TermTile.app` passed after rendering the gallery and arming the
  packaged passive update probe.
- Live local `0.2.6` candidate checks confirmed iTerm content-drag and screenshot-region drags kept
  the focused `ChangeFabric` window bounds unchanged; evidence is recorded in
  `docs/verification/release-v0.2.6-local.md`.
- Published artifact verification for v0.2.6 is recorded in `docs/verification/release-v0.2.6.md`.

At the end of every implementation turn, report:

- Current phase and substep.
- Approximate total progress percentage.
- Validation run in that turn.
- Whether local nits, polish, flakes, or cleanup remain.
- Next steps, including whether more work is required.

## Context

TermTile already has Sparkle update support and a menu-bar extra. Users should be able to see when
Sparkle reports that an update is available:

- a small indicator on the menu-bar glyph;
- an attention indicator on the overflow/ellipsis control;
- the existing "Check for Updates" command should still open the real Sparkle update flow.

The design must stay modular. Sparkle belongs in the executable target, not in `TermTileCore` or
`TermTileKit`. MacFaceKit owns reusable menu/button primitives, so a generic overflow attention API
belongs upstream in MacFaceKit rather than as a checkout patch or TermTile-only workaround.

## Verified Premises

- `Sources/TermTile/Updater.swift` owns Sparkle wiring and lazy-starts update checks.
- `Sources/TermTile/MenuBarContent.swift` owns the current overflow action list.
- `Sources/TermTile/TermTileGlyph.swift` owns the menu-bar glyph rendering.
- `TermTileKit` is the app logic layer and should not import Sparkle.
- Current MacFaceKit `MenuAction`/`OverflowMenu` does not expose a badge or attention API.
- Sparkle's passive probe API is `checkForUpdateInformation()`.
- Sparkle's foreground user command remains `checkForUpdates()`.
- Sparkle delegates are weak and must be retained by TermTile.

Every premise above must be re-verified from real code during the relevant OBSERVE step before BUILD.

## Brutal Audit

### Dependency inversions to avoid

- Do not put Sparkle or update availability in `TermTileKit` or `MenuBarViewModel`.
- Do not make `TermTileUserDriver` own passive update state; it is a foreground dialog adapter.
- Do not patch `.build/checkouts/MacFaceKit`.
- Do not parse appcasts, GitHub releases, XML, or raw update URLs in TermTile.
- Do not create a second badge state independent of Sparkle-derived availability.

### Bundled tasks to split

- Availability state model.
- Testable updater/probe adapter.
- Sparkle delegate-to-state mapping.
- Probe trigger policy.
- Menu-bar glyph badge.
- Overflow ellipsis badge through MacFaceKit.
- Docs/privacy updates.
- Full validation and code review.

### Traps and edge cases

- `startUpdater()` can trigger Sparkle permission or update UI if used casually.
- `checkForUpdatesInBackground()` is scheduler-oriented and not the passive badge probe.
- `checkForUpdateInformation()` is passive, but does not offer updates and ignores skipped versions.
- `canCheckForUpdates` is menu validation, not proof no session is active.
- `sessionInProgress` must guard duplicate checks.
- A pre-menu-open dot requires a proactive network update-information probe.
- Proactive probing changes the user-facing network/privacy behavior and must be documented.
- Swift observation of a long-lived `Updater` owned by `TermTileApp` must be proven by test or manual UI verification.
- A small menu-bar dot must not break the 22-point menu-bar extra constraints or template-image treatment.

### Do now

- Document this plan and keep it current.
- Add red-first source-boundary and behavior tests.
- Build a single app-target update availability source.
- Wire passive Sparkle probing without duplicate update discovery.
- Add the menu-bar glyph indicator once state is reliable.
- Update docs for any proactive network behavior.

### Depends on future state

- The exact MacFaceKit overflow badge API depends on inspecting and modifying the real local MacFaceKit
  repo, validating that repo, publishing or otherwise making a consumable version, then bumping TermTile.
- The exact probe trigger policy depends on packaged-app verification that no unwanted Sparkle prompt or
  focus-stealing behavior is introduced.

## Execution Plan

### Phase 0: Baseline and plan lock

1. OBSERVE: inspect `git status`, target graph, update files, tests, docs, and MacFaceKit surfaces.
2. RED: add or confirm a source-boundary test proving `TermTileKit` does not import Sparkle.
3. RED: add or confirm a source-invariant test proving `Updater` does not parse update feeds itself.
4. VERIFY: run the focused boundary/invariant tests.
5. BUILD: fix only baseline issues discovered by those tests.
6. PITSTOP:
   - Look back: inspect real code and current test output; verify the dependency graph from files.
   - Look back: fix any nits, polish, flakes, or cleanup before continuing.
   - Look forward: revise later phases if Sparkle, target ownership, or MacFaceKit APIs differ from the verified state.

### Phase 1: Update availability value

1. OBSERVE: inspect existing app-target model conventions and test styles.
2. RED: test initial availability state does not produce an attention indicator.
3. RED: test available state produces `hasAvailableUpdate == true`.
4. RED: test checking, unavailable, and failure states do not produce update attention.
5. BUILD: add a small app-target `UpdateAvailability` value with minimal computed helpers.
6. VERIFY: run the focused availability tests.
7. PITSTOP:
   - Look back: inspect the enum, helpers, and test output; verify no UI copy or Sparkle object leaked into the value.
   - Look back: fix naming, duplication, or over-modeling immediately.
   - Look forward: adjust the state shape now if version text or error handling needs are proven by tests.

### Phase 2: Testable updater probe port

1. OBSERVE: inspect `Updater`, current Sparkle startup paths, and existing update wiring tests.
2. RED: fake update client records passive information checks.
3. RED: `refreshAvailability()` calls passive information check, not foreground UI.
4. RED: `refreshAvailability()` does not start a new probe while a session is active.
5. RED: `checkForUpdates()` still calls foreground Sparkle update UI.
6. BUILD: introduce the smallest internal protocol/adapter needed to test `Updater`.
7. VERIFY: run focused updater tests.
8. PITSTOP:
   - Look back: inspect adapter boundaries and test output; verify no duplicate discovery logic exists.
   - Look back: fix awkward abstraction, actor-isolation warnings, or test fragility immediately.
   - Look forward: confirm delegate wiring can be added without changing UI-facing state.

### Phase 3: Sparkle delegate-to-state wiring

1. OBSERVE: inspect vendored Sparkle headers and current fallback path before editing.
2. RED: simulated `didFindValidUpdate` sets availability to available.
3. RED: simulated no-update callback clears availability.
4. RED: simulated error callback does not show update attention.
5. RED: passive check finish clears checking state.
6. BUILD: retain and pass an `SPUUpdaterDelegate` for both custom and stock fallback updaters.
7. BUILD: keep `TermTileUserDriver` limited to foreground dialog translation.
8. VERIFY: run updater wiring and source-invariant tests.
9. PITSTOP:
   - Look back: inspect initializer paths, delegate retention, fallback parity, and test output.
   - Look back: fix lifecycle or weak-delegate mistakes immediately.
   - Look forward: if Swift observation cannot publish cleanly, revise the ownership model before UI work.

### Phase 4: Probe trigger policy

1. OBSERVE: inspect Info.plist generation, update docs, and current lazy-start comments.
2. RED: selected lifecycle trigger invokes exactly one passive probe.
3. RED: repeated menu/app appearances do not spam checks while active or recently checked.
4. RED: manual "Check for Updates" remains foreground and enabled according to Sparkle state.
5. BUILD: implement the least surprising verified policy:
   - if a proactive startup probe is proven safe, trigger `refreshAvailability()` on startup;
   - otherwise trigger on first menu open and document that the icon dot appears after the first probe.
6. VERIFY: run focused tests and packaged app smoke with clean preferences.
7. PITSTOP:
   - Look back: verify real prompt, focus, and network behavior from the packaged app.
   - Look back: fix trigger behavior or docs/privacy text before continuing.
   - Look forward: update UI plan if availability cannot be known at launch.

### Phase 5: Menu-bar glyph indicator

1. OBSERVE: inspect `TermTileGlyph`, menu-bar label wiring, and existing render/accessibility tests.
2. RED: glyph without update state preserves current behavior.
3. RED: glyph with update state exposes a stable update-available visual path.
4. RED: glyph frame remains stable with and without the dot.
5. BUILD: add `TermTileGlyph(hasAvailableUpdate:)` with default `false`.
6. BUILD: wire `MenuBarExtra` label to the single updater availability source.
7. VERIFY: run focused render/accessibility tests and native screenshot or gallery checks.
8. PITSTOP:
   - Look back: inspect screenshots, dimensions, accessibility, and test output.
   - Look back: fix contrast, spacing, or frame polish immediately.
   - Look forward: reuse the same boolean for overflow attention.

### Phase 6: MacFaceKit overflow attention API

1. OBSERVE: inspect local MacFaceKit repo, package versioning, tests, and existing menu/button APIs.
2. RED: existing `MenuAction` callers compile unchanged.
3. RED: an action can opt into generic attention state.
4. RED: `OverflowMenu` shows attention on the ellipsis button when any action requires attention.
5. BUILD: add a generic, reusable MacFaceKit attention/badge API.
6. VERIFY: run MacFaceKit's test/lint gate.
7. BUILD: publish or otherwise make a consumable MacFaceKit version.
8. PITSTOP:
   - Look back: inspect MacFaceKit diff, API shape, visuals, and tests.
   - Look back: fix API or visual polish before TermTile consumes it.
   - Look forward: if release is blocked, stop rather than patching `.build/checkouts`.

### Phase 7: Consume MacFaceKit attention in TermTile

1. OBSERVE: inspect resolved dependency state after MacFaceKit is available.
2. RED: TermTile depends on the intended MacFaceKit version/revision.
3. RED: update-available state marks the update overflow action as attention-worthy.
4. RED: unavailable/checking/error states do not mark the overflow action.
5. BUILD: update `Package.swift`/`Package.resolved` through normal dependency resolution.
6. BUILD: wire `MenuBarContent.overflowActions` to the generic MacFaceKit API.
7. VERIFY: run focused menu/accessibility tests.
8. PITSTOP:
   - Look back: inspect dependency diff, checkout status, and tests.
   - Look back: fix API mismatch, visual copy, or flakes immediately.
   - Look forward: confirm only docs and final validation remain.

### Phase 8: Docs and release-facing polish

1. OBSERVE: inspect README, release docs, privacy copy, and verification docs.
2. RED: if proactive probing exists, docs mention update availability network checks.
3. RED: docs distinguish passive indicators from the foreground install flow.
4. BUILD: update docs and durable decisions to match actual behavior.
5. VERIFY: run doc/source readiness tests.
6. PITSTOP:
   - Look back: inspect docs against implemented behavior and test output.
   - Look back: fix stale or misleading copy immediately.
   - Look forward: only proceed when docs match shipping behavior.

### Phase 9: Final validation and review

1. VERIFY: run focused updater, glyph, menu, dependency, docs, and packaging tests.
2. VERIFY: run `swift build && swift test && swiftlint --strict`.
3. VERIFY: run packaged app smoke.
4. VERIFY: use native UI screenshots/gallery for menu-bar UI; use `chromwebdevtools` only for web/docs previews.
5. REVIEW: run a code-review agent before finalizing.
6. BUILD: fix every actionable nit, polish item, flake, or cleanup from validation/review.
7. VERIFY: rerun affected tests, then rerun the full gate after code changes.
8. FINAL PITSTOP:
   - Look back: inspect final diff, test output, dependency files, docs, and repo status.
   - Look back: verify the feature actually works and manual update checks still use Sparkle.
   - Look forward: identify only true external release blockers or future enhancements.

### Phase 10: Drag-reorder fullscreen/focused-window QOL investigation

Status: Complete locally.

1. OBSERVE: reproduce the report that with "Reorder windows on drag" enabled, a fullscreened or focused
   target window snaps back to the grid after commands such as selecting text and pressing Command-C or
   taking a screenshot with Command-Shift-4.
2. RED: add the smallest failing test around the real event classifier/drag monitor behavior. The test
   must distinguish an actual completed drag from command-key focus/copy/screenshot interactions.
3. BUILD: fix the root invariant in the drag-event/window-event authority, not in a UI toggle workaround.
4. VERIFY: run drag monitor, tiling actor, and menu view-model tests; manually exercise copy/content-drag
   and screenshot workflows with drag reorder enabled.
5. PITSTOP:
   - Look back: inspect real event timing, window frame events, and test output; verify the command
     workflows no longer snap a fullscreen/focused window back to the grid.
   - Look back: fix nits, flakes, and cleanup immediately.
   - Look forward: decide whether release notes or docs need to mention the behavior fix.

Outcome: completed locally. The focused unit tests cover the root classifier, and live local candidate
checks against iTerm2 content-drag and `screencapture -ic` screenshot-region drag are recorded in
`docs/verification/release-v0.2.6-local.md`.
