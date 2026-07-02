# TermTile backlog

Taxonomy: `#N · title · S0|S1|S2|DONE` (S0 captured · S1 stoke-planned · S2 brutally
audited). Loop beats route S0/S1 through stoke-01-launch before building. Dependencies
are explicit — do not start a task whose `blocked-by` is not DONE.

Authorities: `docs/research/macos-tiling-research.md` (verified research),
`docs/product/spec-draft.md` (provisional spec), `.engine/MEMORY.md` (PROVE semantics —
live surface = real windows + screencapture evidence, not Chrome/curl).

## Phase A — grounded-information spikes (micro red-first probes)

Goal: replace every research open-question with observed fact from THIS Mac before
committing build architecture. Each spike lands as a small SPM target/test + a findings
note in `docs/research/spikes/NN-<slug>.md`. Spike code is throwaway-quality but
committed; findings notes are the durable output.

#1 · SPM package skeleton: menu-bar app target + Swift Testing wired, swift build/test green · DONE
  (2026-07-02: swift test 2/2 green + invert-check red; live launch proven — AX "status menu"
  + CGWindowList layer-25 window; evidence: docs/verification/task1-spm-skeleton.md)
  Foundational. Package.swift (macOS 14+, Swift 6), Sources/TermTile/ executable target,
  Tests/TermTileTests/ (Swift Testing `@Suite`/`@Test`, per RememBar) with one real
  red-first test. ONE NAME EVERYWHERE from commit 1: target/product `TermTile`, bundle ID
  `dev.ecn.apps.termtile` (RememBar's naming drift required cleanup machinery — audit §8.9).
  Unblocks every other task; also turns the loop's build∧test signals live.
#2 · Spike: Accessibility TCC — detect + prompt (AXIsProcessTrustedWithOptions) · DONE
  (2026-07-02: swift test 4/4 green + invert-check red; PROVE live on real TCC surface —
  shell-exec trusted=true via terminal attribution, bundled .app trusted=false with denied
  cdhash-pinned row observed in system TCC.db; findings:
  docs/research/spikes/02-accessibility-tcc.md. Decision: Developer ID lands with #13.)
  blocked-by #1. Findings: how trust behaves for an unsigned dev binary vs bundled .app.
  KNOWN (audit §6): ad-hoc signing pins TCC to the per-build cdhash → every rebuild resets
  the Accessibility grant. Measure the dev-loop pain; decide when Developer ID lands.
#3 · Spike: enumerate iTerm2 windows (AXUIElementCreateApplication → kAXWindowsAttribute) · DONE
  (2026-07-02: swift test 6/6 green + invert-check red; PROVE live on real iTerm2 — tabs =
  ONE AXWindow (15→16 with 3 tabs); _AXUIElementGetWindow ids match CGWindowList 17/17 AND
  equal AppleScript window ids; minimized windows stay enumerated with real frames; findings:
  docs/research/spikes/03-iterm2-window-enumeration.md. Fullscreen edge → #7, Spaces
  completeness → #9.)
  blocked-by #2. Findings: do tabs present as one AXWindow? window IDs via
  _AXUIElementGetWindow? minimized/fullscreen filtering (kAXMinimizedAttribute,
  AXSubrole standard-vs-panel)?
#4 · Spike: set one iTerm2 window frame (size→position→size, AXEnhancedUserInterface off) · DONE
  (2026-07-02: swift test 11/11 green + invert-check red; PROVE live — 5-frame battery on
  spike-created iTerm2 window 78164: err=0, readback exact, settle <50ms, 0.2-24ms/op;
  min clamp 73x67 iTerm2 / 73x29 WezTerm; WezTerm full parity, window 78184, no
  AppleScript needed; findings: docs/research/spikes/04-frame-writes.md. Cross-display
  clamp + EUI=true interference unobservable here → recorded as explicit UNVERIFIED.)
  blocked-by #3. Findings: does iTerm2 honor kAXPosition/kAXSize promptly? min-size
  clamping? latency per write? Repeat probe on WezTerm for parity (app-agnostic goal).
#5 · Spike: AXObserver per-pid — windowCreated/moved/destroyed events for iTerm2 · DONE
  (2026-07-02: swift test 13/13 green + invert-check red; PROVE live on real iTerm2 —
  3 lifecycles n=3: app-level registration fires ALL FOUR notifications incl. destroyed
  (--no-perwin run CONTRADICTS research :23-24 per-window-required claim); ordering
  strict created→resized→moved→destroyed; moved/resized 6-14ms in-process; destroyed
  element id unresolvable (-25201) → #9 needs element-hash→id map; naive Swift 6
  closure shape compiles clean; findings: docs/research/spikes/05-axobserver-events.md.
  ~5s undo-close retention anomaly recorded → #9 must ignore unknown-hash destroys.)
  blocked-by #3. Findings: event latency/ordering; kAXUIElementDestroyed per-window
  registration; CFRunLoop→Swift 6 strict-concurrency bridging (dedicated run-loop thread?).
#6 · Spike: drag-end detection — debounced kAXMoved vs CGEventTap/NSEvent global mouse-up · DONE
  (2026-07-02: swift test 36/36 green [12 new MoveClassifier] + invert-check red 8-issue oracle;
  PROVE live on real iTerm2 window 78924 — REAL MoveClassifier tags a programmatic move internal
  vs recorded expectation / external vs empty / external vs +100-shifted on the SAME AX-delivered
  frame [dragprobe B1-gated on actual AXWindowMoved fire]; mouseprobe: leftMouseUp CGEventTap
  installs+enabled from bg process [Input-Monitoring preflight=true, non-prompting]. Findings:
  docs/research/spikes/06-drag-end-detection.md. RECOMMEND global mouse-up (cadence-independent).
  B2 ledger contract: caller records ONE PendingMove per AX write. Live human-drag cadence +
  mouse-up reception recorded UNVERIFIED [needs human-in-loop]. Plan: .engine/state/stoke-plan-6.md.)
  blocked-by #5. Read Rectangle + Amethyst source first (Trace), then probe both; pick
  with evidence. Also verify self-move tagging (ignore our own AX writes).
#7 · Spike: macOS native tiling interference — AX frame sets vs Sequoia/Tahoe snap · DONE
  (2026-07-02: swift test 44/44 green [8 new NativeTilingSettings] + invert-check red; PROVE
  live on real com.apple.WindowManager — tilecheck exercises the REAL Core resolver + round-trips
  ALL 4 Sequoia tiling keys write-false→readback→restore, PASS=true, domain fully restored [all
  keys absent pre AND post]. Findings: Q1 native tiling is user-gesture-only → does NOT contest
  AX writes [auto case inherits spike-04's stable readback; manual-tile-resist UNVERIFIED,
  human-in-loop]; Q2 global suppression = 4 WindowManager keys [proven controllable], NO per-app
  opt-out API. Fixed pre-existing dragprobe defer-restore bug [exit() skips defer → TRAP-12 +
  axprobe-no-defer.sh]. Findings: docs/research/spikes/07-native-tiling-interference.md; plan:
  .engine/state/stoke-plan-7.md. Phase A grounding COMPLETE.)
  blocked-by #4. Findings: does native tiling fight programmatic frames; per-app or
  global suppression options.

## Phase B — the informed build (unblocked by Phase A evidence)

#8 · Layout math: pure TermTileCore module — (windowCount, visibleFrame, gaps) → column-of-2 frames · DONE
  (2026-07-02: swift test 24/24 green [13 migrated + 11 TileLayout property tests] + invert-check
  red across N=1..12; ADR-0001 four-target split LIVE [Core←Kit←TermTile + AXProbe]; core-purity.sh
  fail-closed [catches @preconcurrency import], bait-proven; TileLayout.frames public, column-major.
  Skeptic audit caught F1 BLOCKER: cross-module AppIdentity needs public. Plan: .engine/state/
  stoke-plan-8.md; receipt: .engine/state/receipt.md Row 8.)
  blocked-by #1 only (pure function, no AX). ARCHITECTURE IS BINDING: docs/decisions/
  0001-functional-core-imperative-shell.md — this task ALSO creates the target split
  (TermTileCore/TermTileKit/TermTile/AXProbe), migrates AppIdentity/WindowFiltering/
  AccessibilityTrust into their targets, and adds .engine/checks/core-purity.sh.
  columns=ceil(N/2), even widths, last column 1 window if N odd; property tests across
  N=1..12 + edge frames. TDD showcase task.
#9 · Window state model: reducer + expectation ledger (ADR-0001 rules 3-4) · DONE
  (2026-07-02: swift test 59/59 green [+15 WindowStateReducer] + invert-check red [.internal→
  .external flip fails 5 classification tests incl. keystone, restored green]; PURE Core [rule 3
  delivered], core-purity.sh PASS. WindowState/TrackedWindow/WindowEvent/FrameCommand/
  WindowStateReducer land in TermTileCore. Skeptic caught: consume-by-frame-match [not first-for-
  window — MoveClassifier returns no match index], non-invertible external test [rewrote to assert
  pending-survives], deferral-reason-wrong [was FL-1, corrected to port-co-design+no-commands-to-
  write]. Spike-05 anomaly guards tested: destroyed/moved unknown-id no-op, nil-frame no-op. Plan:
  .engine/state/stoke-plan-9.md; receipt: .engine/state/receipt.md Row 8.)
  blocked-by #3, #5, #8 (needs the target split). Pure reducer (State, WindowEvent) →
  (State, [FrameCommand]) in Core; pending-expectation ledger (CGWindowID → frame ±
  epsilon + deadline) classifies moves internal/external as a pure function. Swindler =
  pattern reference only, never a dependency.
  DEFERRED to #18: TilingActor + WindowSystem port + AX adapter + in-memory fake
  [DEP: shape — port shape is adapter-driven and the reducer emits no commands until #10's cases, so the actor's
  write path is un-exercisable until #10's cases land] → #18. Recorded run-loop-hosting DESIGN
  decision (spike-05:62/103): app-level AXObserver registration (one CFRunLoopSource/pid, low
  event rate 6-14ms) bridged into an AsyncStream<WindowEvent> on the MAIN run loop is sufficient;
  move to a dedicated run-loop thread ONLY if main-thread contention is observed live.
#10 · Retile policy: command-emitting reducer cases (pure Core) · DONE
  (2026-07-02: swift test 71/71 green [+12 — 8 TileEngine, 4 reducer-emission] + invert-check red
  [structural gate flipped so .moved retiles → "moved emits []" fails with 2 real FrameCommands,
  restored green]; PURE Core [ADR-0001 rule 1], core-purity.sh PASS. TileConfig + TileEngine.
  retileCommands [idempotence no-op filter] land in TermTileCore; reduce gains config:.disabled
  default + windowSetChanged gate. Skeptic caught 3 BLOCKERs: (R1) "one AX write per command" is
  false [size→pos→size=3 writes] → reduce records NO pendings, actor does per-write [#18/#19];
  (R2) gate on actual set-change not event-kind [phantom destroy/nil-frame no-retile]; (R3) full
  downstream repoint. SCOPED from the old #10: the TilingActor/port/fake/AX-adapter/live-iTerm2
  PROVE split to #18/#19 [real DEP — un-exercisable until reduce emits commands, this beat's work].
  Plan: .engine/state/stoke-plan-10.md; receipt: .engine/state/receipt.md Row 8.)
  blocked-by #4, #5, #8, #9. Pure retile POLICY only (ADR-0001 rule 1): TileConfig + TileEngine.
  retileCommands mapping windows→TileLayout slots with idempotence, and reduce's create/destroy
  command-emission on an actual window-set change when enabled. Records no pendings (the actor
  does, per AX write). PROVE = swift test + invert-check (pure Core, like #8/#9); the live-AX
  grid-snap proof is #19.
#18 · Tiling shell: WindowSystem port + in-memory fake + TilingActor · DONE
  (2026-07-02: swift test 78/78 green [+7 TilingActor] + invert-check red [apply records only the
  final target → keystone pending==9 fails, 3 recorded; restored green]; PROVE = Kit-with-fake, the
  actor executes in-process against the real Core reducer/engine. WindowSystem port [async
  enumerate/read/write + AsyncStream<WindowEvent>], InMemoryWindowSystem fake, TilingActor land in
  TermTileKit; core-purity.sh PASS [Kit, not Core]. Keystone: activate→3 writes at slot targets→9
  pendings [size→pos→size trio per window]→replayed echoes classify internal, drain to empty, ZERO
  re-write [ADR rule-3 feedback break]. Skeptic caught R1 BLOCKER [sync Sendable port can't be
  witnessed by an actor fake → async port], R2 [created-4th → 2 writes: id3 retarget + id4], R3/R4/R5.
  Plan: .engine/state/stoke-plan-18.md; receipt: .engine/state/receipt.md Row 8.
  AX adapter + element→id map + destroy-dedupe + messaging-timeout + LIVE grid-snap PROVE = #19.)
  blocked-by #10. Builds (absorbed from the old #10, un-exercisable until #10's commands landed):
  the WindowSystem port (enumerate/readFrame/writeFrame + AsyncStream<WindowEvent>), an in-memory
  fake for tests, and TilingActor in Kit owning the AX adapter handle + a cached TermTileCore.
  WindowState snapshot (instant reads, serialized async writes, ~1s AX messaging timeout), the
  element(CFHash)→CGWindowID map + destroy-dedupe (spike-05: destroy ids unresolvable -25201).
  The actor records ONE PendingMove per AX WRITE via WindowState.recording (NOT per command —
  size→pos→size = 3 writes). Run-loop-hosting DESIGN already made (#9): app-level AXObserver
  bridged to an AsyncStream on the MAIN run loop. Tested against the fake (no live AX here).
  [DEP: shape — the actor's apply-commands write path cannot exist until #10's reducer emits
  commands] → #10.
#19a · AX adapter WRITE-PATH (real WindowSystem: enumerate/readFrame/writeFrame) + AXGeometry flip + LIVE iTerm2 grid-snap PROVE · DONE
  (2026-07-03: swift test 86/86 green [+5 AXGeometry] + invert-check red [AXGeometry sign flip →
  all 5 flip tests fail, restored green]; PROVE LIVE on real iTerm2 — the REAL TermTileKit
  AXWindowSystem adapter enumerated 9 tileable windows [throwaways present=true] and writeFramed 4
  throwaway windows to a real TileLayout 2×2 grid: readback EXACT [dOrigin=0 dSize=0 all snapped],
  screencapture docs/verification/task19a-grid.png shows the clean grid, PASS=true rc=0, session
  restored to baseline 17 windows. AXGeometry [Core, pure] + AXWindowSystem [Kit, actor, events()
  = finished-empty stub] land; core-purity.sh PASS. Consent restructure: window create/close moved
  to the AppleEvents-consented shell + AXProbe `livecheck-ids` [AX-only, terminal-attributed
  Accessibility trust], so a rebuilt ad-hoc binary proves live without a blocking Automation-
  consent dialog [spike-02 cdhash reset]. Hit TRAP-14 [bare `Task {` from @MainActor main + sem.wait
  = deadlock → Task.detached + pre-resolved NSScreen; axprobe-detached-task.sh]. Plan:
  .engine/state/stoke-plan-19.md; receipt: .engine/state/receipt.md Row 8. events()+WindowIDMap+
  new-window-snap = #19b.)
  (SPLIT from old #19 by stoke-plan-19.md §E brutal audit — the AXObserver→AsyncStream event
  bridge is genuinely-new run-loop-thread-confined code, not a promotion; FL-1 is met by the live
  grid snap alone, so #19b isolates the concurrency risk.)
  blocked-by #18. Promote AXProbe enumerate/setFrame/observe→ WRITE side into TermTileKit
  AXWindowSystem (imports ApplicationServices; the ONLY control surface — ADR rule 2):
  size→pos→size writes, AXEnhancedUserInterface disable/restore via `defer` (actor method returns
  normally — NOT inline; TRAP-12/axprobe-no-defer.sh are exit()-specific, guard only AXProbe),
  min-size clamp READBACK logged-only (iTerm2 73×67, never hardcode, no compensation — YAGNI).
  AXGeometry (pure Core, red-first): Cocoa→AX top-left flip off the ORIGIN screen (never .main).
  events() = finished empty stub this beat. PROVE (FL-1): AXProbe `livecheck` creates throwaway
  iTerm2 windows, the REAL adapter writeFrames them to a real TileLayout grid, readback snaps;
  screencapture → docs/verification/. Plan: .engine/state/stoke-plan-19.md.
#19b · AX adapter EVENT BRIDGE (AXObserver→AsyncStream) + LIVE new-window snap PROVE · DONE
  (2026-07-03: swift test 91/91 green [+5 WindowIDMap] + invert-check red [consumeDestroy dedupe
  dropped → keystone once-then-nil fails, restored green]; PROVE LIVE on real iTerm2 — AXProbe
  livecheck-events armed the REAL adapter.events() on the main run loop; a shell-created window (80589)
  fired a real .created through the bridge; the running TilingActor snapped it 665×458→1704×1009 EXACT
  [dOrigin=0 dSize=0]; the snap's .resized echo classified .internal [ONE echo, no re-tile — loop break
  live]; on close a real .destroyed carried the RIGHT id via WindowIDMap [not -25201/0,
  destroyedMatchesCreated=true]; screencapture docs/verification/task19b-events.png, PASS=true rc=0,
  session restored to 17. WindowIDMap [pure Core, CoreGraphics-only] + real AXWindowSystem.events()
  [three module-global nonisolated(unsafe): continuation + WindowIDMap + RETAINED AXObserver — audit F1
  BLOCKER: AddSource retains the source not the observer; @convention(c) callback on CFRunLoopGetMain()
  in CFRunLoopCommonModes; onTermination teardown; not-running→finished-empty] + AXProbe livecheck-events
  [consent-free, Task.detached + main-pump, TRAP-14] land; core-purity + axprobe-detached-task PASS.
  Skeptic caught F1 BLOCKER [observer retention] + F2 [arm-before-create] + F3 [map create-seed-only,
  enumerate-seed → #12] pre-build. Hit TRAP-15 [first run false-passed origin-only/no-settle → fixed:
  settle-before-snap + size assertion]. Plan: .engine/state/stoke-plan-19b.md; receipt: receipt.md Row 8.
  DEFERRED: WindowIDMap enumerate-seed → #12; cross-Space/fullscreen + clamp-compensation → #15.)
  blocked-by #19a. Owns: the run-loop-thread-confined WindowIDMap (create-seed + destroy-resolve
  via spike-05 -25201 + dedupe), the module-global continuation bridge (ADR rule 4 — a
  @convention(c) callback can't capture self), the internal-echo-swallow loop proven LIVE, AND the
  re-homed cross-Space kAXWindows-completeness + fullscreen-enumeration + per-window-destroyed
  questions. PROVE (FL-1): a freshly-created iTerm2 window fires a .created WindowEvent through
  adapter.events() and the running TilingActor snaps it to grid; screencapture → docs/verification/.
#11 · Drag snap-reorder: nearest-slot assignment on drag end + shuffle · DONE
  (2026-07-03: swift test 102/102 green [+9 pure reorder incl. permutation property N=2..8 + 2 actor]
  + TWO invert-checks red [pure argmin flip → 12 issues; actor state-drop → 5 issues, restored green];
  PURE Core reorder policy + Kit actor method, core-purity.sh PASS. TermTileCore.TileEngine.
  reorderCommands [drop-center → nearest slot via stable argmin, list remove+insert shuffle,
  retileCommands snap; leading guard disabled/untracked/empty; N=1 snaps back] + TilingActor.
  handleDragEnd [reads cache, calls pure fn, updates state.windows, apply records size→pos→size
  pending trio per write] land. Reducer .moved/.resized UNTOUCHED [mid-drag move updates cache, no
  reorder — drag-END is a mouse-up, not an AX notification]. PROVE = in-process actor-over-fake [#18
  non-adapter bar]: real TilingActor snapped id1→slot3, snapshot [2,3,4,1], every write hits new slot,
  pending==writes×3. Skeptic caught B1 [leading-guard order before geometry] + N1 [exact-frame seeding
  for the idempotent case] + R3 [PROVE-bar]. Plan: .engine/state/stoke-plan-11.md; receipt: receipt.md
  Row 8. DEFERRED: live CGEventTap mouse-up TRIGGER + live reorder screencapture → #12; true cursor
  drop-point + final-move race → #12.)
  blocked-by #6, #19b (needs adapter.events() for external-move/drag detection).
#12 · Menu-bar app shell: toggle, target-app picker, launch-at-login, settings — SPLIT by
  stoke-plan-12a.md into #12a/#12b/#12c (four features across three PROVE-surfaces; precedent
  #19→#19a/b). Original authorities: SwiftUI MenuBarExtra `.window` style (RememBar; delegate-
  adaptor gotcha: init() is the reliable hook); SMAppService.mainApp (audit §8.6); UserDefaults
  behind a protocol (audit §8.7); permission fix-it row (adapt FileSearchAccessChecker).
#12a · Settings persistence port: AppSettings + SettingsStore + UserDefaultsSettingsStore + fake · DONE
  (2026-07-03: swift test 107/107 green [+5] + invert-check red [break load()→.defaults → tests 4&5
  fail, restored]; PROVEN LIVE via EXTERNAL process — AXProbe settingscheck drove the REAL
  UserDefaultsSettingsStore to the actual macOS defaults DB, a separate `defaults read` observed
  isEnabled=1 targetBundleID=ghostty, suite deleted. AppSettings [pure value type] + SettingsStore
  [sync protocol] + UserDefaultsSettingsStore [suiteName:String? → Sendable; per-key object/string
  fallback] + lock-guarded @unchecked Sendable InMemorySettingsStore fake [sync port can't be an
  actor — inverse of WindowSystem]; all in Kit, core-purity green. Skeptic caught 3 BLOCKERs pre-build
  [actor-fake-impossible, wrong-invert-only-reddens-test-1, parallel-suite-race]. Plan:
  .engine/state/stoke-plan-12a.md; receipt: .engine/state/receipt.md Row 8; verification:
  docs/verification/task12a-settings.md.)
  blocked-by #1 (DONE). Kit, pure-Foundation seam. Persist ONLY MVP-user-changeable state:
  isEnabled (toggle, default false) + targetBundleID (picker, default com.googlecode.iterm2).
  Gap = hardcoded constant (→ #17); launchAtLogin source-of-truth = SMAppService.status (→ #12b),
  NOT UserDefaults (double-source bug). PROVE = swift test incl. LIVE UserDefaults(suiteName:)
  cross-instance round-trip + invert-check. Plan: .engine/state/stoke-plan-12a.md.
#12b · Launch-at-login: SMAppService.mainApp behind a LoginItem protocol + fake · S0
  blocked-by #12a. Logic/registration API testable via fake now; the LIVE login-item
  registration is observable only from a bundled .app.
  [DEP: blocked-by #13 — SMAppService.mainApp requires the packaged .app + login-item domain; a
  `swift run` binary can't register a real login item, so the LIVE prove needs #13's bundle] → #13
#12c · MenuBarExtra shell wiring: toggle→TilingActor.activate, target-app picker, permission fix-it row · S0
  blocked-by #12a, #12b, #19b (needs the full engine incl. events()). SwiftUI MenuBarExtra
  `.window` style (RememBar; init() is the reliable delegate hook). Composes SettingsStore +
  LoginItem + AccessibilityTrust probe + Privacy_Accessibility deep link into the shell. PROVE =
  LIVE app launch + AX menu-bar enumeration (System Events → menu bar item) + CGWindowList
  layer-25 window — NOT pixels (TRAP-1). Includes bundled-app prompt-path UX observation (spike 02).
#13 · Packaging + CI: .app bundle, codesign, smoke scripts, test/release workflows · S0
  blocked-by #12c. Authority: docs/research/remembar-audit.md COPY/ADAPT table. Build script
  (Info.plist heredoc, LSUIElement, sips/iconutil icon; glob resources — audit §8.4),
  inside-out ad-hoc codesign no --deep + verify strict, test-packaged-app.sh launch proof,
  monotonic build number (NOT dots-stripped — audit §8.5), SwiftLint + Semgrep + Dependabot,
  release.yml with VirusTotal + provenance attestation + SHA-256 ("virus testing"), AND
  swift test in CI gating release (RememBar's biggest gap — audit §8.1-8.3). Includes a
  stable signing identity (Developer ID or self-created cert) so .app TCC grants survive
  rebuilds (spike 02 proved ad-hoc cdhash pinning voids grants; required before #14).
#14 · E2E proof: fresh-boot flow — grant TCC, toggle on, spawn 5 terminals, verify grid, drag-reorder · S0
  blocked-by #11, #13, #19b. Recorded evidence (screencaptures) into docs/verification/.

## Phase C — deferred (do not pull forward without a reason)

#15 · Multi-display + Spaces awareness · S0
  [DEP: shape — needs #19b's live engine surface; also owns the multi-display AXGeometry flip
  reference (#19a uses the single origin screen)]
#16 · Sparkle auto-updates + release pipeline · S0
  [DEP: blocked-by #13]
#17 · Gap/padding settings UI + per-app profiles · S0
  [DEP: shape — post-MVP polish]
