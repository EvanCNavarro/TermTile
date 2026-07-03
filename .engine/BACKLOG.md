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
#12b · Launch-at-login: SMAppService.mainApp behind a LoginItem protocol + fake · DONE
  (2026-07-03: swift test 112/112 green [+5 LoginItem] + invert-check red [swap map arms
  .notRegistered↔.enabled → keystone 2 issues, restored]; PROVE — correctness by the unit mapping
  test across ALL FOUR real SMAppService.Status cases; READ path proven LIVE via AXProbe logincheck
  [real SMAppServiceLoginItem().status through real ServiceManagement → status=notFound from the
  unbundled binary, no crash/hang, framed liveness-only]. LoginItemStatus + LoginItem [sync Sendable
  port] + SMAppServiceLoginItem [resolves .mainApp per call — SMAppService is non-Sendable NSObject;
  explicit named-case map + @unknown default] + lock-guarded @unchecked Sendable InMemoryLoginItem
  fake [seedable initial status], all in Kit; core-purity + axprobe checks PASS. Skeptic verified
  every API fact against the real SMAppService.h header [no BLOCKERs; 1 MAJOR honesty-of-live-read +
  2 MINORs reconciled]. Plan: .engine/state/stoke-plan-12b.md; receipt: receipt.md Row 8;
  verification: docs/verification/task12b-loginitem.md.)
  blocked-by #12a (DONE). Logic/registration API testable via fake now; the LIVE login-item
  registration is observable only from a bundled .app.
  [DEP: blocked-by #13 — SMAppService.mainApp requires the packaged .app + login-item domain; a
  `swift run` binary can't register a real login item, so the LIVE prove needs #13's bundle] → #13
#12c · MenuBarExtra shell wiring: toggle→TilingActor.activate, target-app picker, permission fix-it row · DONE
  (2026-07-03: swift test 122/122 green [+10 MenuBarViewModel] + invert-check red [break
  toggle→activate wire → keystone writes.count 0==3, restored]; PROVEN LIVE — real .build/debug/
  TermTile launched accessory/no-focus: PROCESS-ALIVE, AX "status menu" [menu bar 2], CGWindowList
  layer-25 status window [TRAP-1: AX+layer not pixels — item parked off-screen X:-4777 by a menu-bar
  manager], and an in-process TERMTILE_SELFTEST proving the REAL setEnabled(true)→UserDefaults
  persist [fresh false→true delta, non-running target so activate inert — zero windows moved].
  MenuBarViewModel [@MainActor @Observable, Kit — injected visibleFrame seam R1, awaits activate R2,
  public liveTrustProbe keeps AccessibilityTrust internal R6] + TargetApp/TargetAppsProviding +
  WorkspaceTargetAppsProvider + fake + MenuBarContent SwiftUI + TermTileApp composition root land.
  No run()/live-event obs here [module-global AXObserver bridge can't host two adapters across a
  target-switch → #14, R3]. HONEST residual: SwiftUI control→VM bindings code-review-only [.window
  popover can't be scripted]; click-to-tile E2E → #14. Skeptic SAFE-WITH-FIXES [7 folded, no split].
  Hit TRAP-17 [buffered-stdout markers lost on SIGTERM → unbuffered stderr; new check]. Plan:
  .engine/state/stoke-plan-12c.md; receipt: receipt.md Row 8; verification:
  docs/verification/task12c-menubar-shell.md.)
  blocked-by #12a, #12b, #19b (needs the full engine incl. events()). SwiftUI MenuBarExtra
  `.window` style (RememBar; init() is the reliable delegate hook). Composes SettingsStore +
  LoginItem + AccessibilityTrust probe + Privacy_Accessibility deep link into the shell. PROVE =
  LIVE app launch + AX menu-bar enumeration (System Events → menu bar item) + CGWindowList
  layer-25 window — NOT pixels (TRAP-1). Includes bundled-app prompt-path UX observation (spike 02).
#13 · Packaging + CI — SPLIT by stoke-plan-13a.md Scope into #13a/#13b/#13c (three PROVE-surfaces:
  local packaging / GitHub-Actions CI / Apple-cert signing; precedent #19→a/b, #12→a/b/c). Original
  authority: docs/research/remembar-audit.md COPY/ADAPT table.
#13a · App bundle + packaging script + packaged-app launch smoke · DONE
  (2026-07-03: swift test 128/128 green [+6 PackagingScriptsTests] + invert-check red [add --deep to
  the bundle sign line → signLines.allSatisfy reddens; the FIRST invert false-passed on a first-match-
  only assertion → strengthened to allSatisfy over ALL sign lines, re-inverted real red; restored];
  PROVEN LIVE bundle-specific [skeptic F3] — scripts/build-app.sh built dist/TermTile.app, codesign
  --verify --deep --strict rc=0, codesign -dv Identifier=dev.ecn.apps.termtile flags=0x2(adhoc); the
  bundled binary launched accessory/no-focus [ALIVE, exec-path under dist/TermTile.app], System Events
  bundle-identifier-of-PID == dev.ecn.apps.termtile [the discriminator vs a bare binary's missing
  value], AX menu-bar-2 status item, CGWindowList layer-25 [TRAP-1 not pixels, X:-4777]; test-packaged-
  app.sh alive=8/8 crash-reports 0->0. build-app.sh [--show-bin-path, plutil -lint'd Info.plist,
  LSUIElement, CFBundleVersion=git rev-list --count=28 never dots-stripped, inside-out ad-hoc sign no
  --deep] + test-packaged-app.sh [kill -0 launch proof, Bundle.module regression guard, no pkill] +
  PackagingScriptsTests [6 positive line-scoped invariants] land. Hit TRAP-18 [Unicode arrow glued to
  $var breaks Bash under set -u → new scripts-ascii-only.sh]. Skeptic SAFE-WITH-FIXES [3 MAJOR folded:
  F1 line-scoped, F2 positive-presence, F3 bundle discriminator]. Plan: stoke-plan-13a.md; receipt:
  receipt.md Row 8; verification: docs/verification/task13a-packaging.md.)
  blocked-by #12c (DONE). Kit-adjacent scripts (no production Swift source change). scripts/build-app.sh
  (swift build -c release --show-bin-path → dist/TermTile.app; Info.plist heredoc LSUIElement + bundle
  id dev.ecn.apps.termtile + monotonic CFBundleVersion=git rev-list --count [NOT dots-stripped, audit
  §8.5]; plutil -lint; xattr -cr; inside-out ad-hoc codesign -s - no --deep; verify --deep --strict) +
  scripts/test-packaged-app.sh (bundle-invariant + foreign-path launch proof, NO pkill/killall) +
  Tests/TermTileKitTests/PackagingScriptsTests.swift (scripts-as-text invariants, red-first). PROVE
  (FL-1, bundle-specific per audit F3): build the .app, codesign -dv Identifier + verify --deep --strict,
  launch Contents/MacOS/TermTile, System Events "status menu" AND bundle-identifier-of-PID ==
  dev.ecn.apps.termtile (discriminator vs bare binary), CGWindowList layer-25 (TRAP-1 not pixels),
  screencapture archival. Icon deferred (LSUIElement = no dock icon, YAGNI). Plan: stoke-plan-13a.md.
#13b · CI wiring: swift test in check.yml + SwiftLint/Semgrep + release.yml · DONE
  (2026-07-03: swift test 134/134 green [+6 WorkflowsTests] + THREE invert-checks red [one per workflow
  file — check.yml swift→npm reddens swift-test-gate+npm-absence; release.yml drop scripts/build-app.sh
  reddens the full-path call; semgrep.yml drop p/secrets reddens the pack], restored green; all 10
  .engine/checks PASS. LOCALLY PROVEN what a no-network beat can prove: the GATED COMMANDS run green on
  THIS repo — `swift test` 134/134 (exactly what check.yml runs) + `swiftlint --strict` rc=0 0-violations
  (exactly what the lint step runs) — and all workflow YAMLs are well-formed via `ruby -ryaml`. check.yml
  REWRITTEN [macos-15; swift build/test + swiftlint --strict; KEEPS name:Check + permissions:contents:read
  per REPOSITORY_POLICY.md, npm placeholder removed] + semgrep.yml [p/security-audit + p/secrets, PR +
  weekly] + release.yml [tag v* → swift test gate → CALLS scripts/build-app.sh → ditto+SHA-256 →
  attest-build-provenance@v4 → VirusTotal via curl+secret → gh release; appcast dropped → #16] +
  .swiftlint.yml [excludes throwaway AXProbe + Tests, trailing_comma off (Swift 6.1), identifier_name
  min_length 1 (geometry math); force_cast kept STRICT, scoped inline at AXWindowSystem.swift:208,211] +
  Tests/TermTileKitTests/WorkflowsTests.swift [6 line-scoped POSITIVE invariants]. dependabot npm entry
  dropped (npm CI gone). Skeptic SAFE-WITH-FIXES [F1 attest@v4, F2 preserve name/permissions+doc-drift,
  F3 invert-per-file, F4 scope force_cast inline, F5 drop npm dependabot — ALL folded]. Fixed a
  self-inflicted too-crude secret invariant [flagged `github.token` — narrowed to require a `${{ }}`
  context]. Plan: .engine/state/stoke-plan-13b.md; receipt: receipt.md Row 8; verification:
  docs/verification/task13b-ci-wiring.md.)
  blocked-by #13a (DONE). Kit-adjacent CI config (no production Swift logic change; 2 comment-only lines
  in AXWindowSystem for the inline lint exemption). LIVE GitHub-Actions execution is external → #20.
  DEFERRED: live workflow runs on GitHub runners (check/semgrep green + tag→release with secrets) + GH-Actions schema validation (actionlint/yamllint absent, no-network to install; ruby proves well-formedness only) [DEP: external — a live CI run needs GitHub runners + configured secrets + a push, all outside a no-network/no-push loop beat] → #20
#13c · Stable signing identity (Developer ID / self-signed cert) so .app TCC grants survive rebuilds · DONE
  (2026-07-03: self-signed 'TermTile Dev Signing' cert in login keychain; designated requirement
  binds to bundle-id + cert root, so the Accessibility grant survives rebuilds — verified via TCC.db.
  Developer ID/notarization deferred to public-distribution decision.)
  blocked-by #13a. Spike 02 proved ad-hoc cdhash pinning voids the Accessibility grant on every rebuild
  (fatal UX for an AX tiler). Establish a stable codesigning identity and re-sign the bundle with it.
  [DEP: external — zero codesigning identities on this machine (security find-identity → 0 valid);
  Developer ID needs an Apple Developer account (network), a self-signed identity needs Keychain UI —
  un-doable in an offline/non-interactive loop beat] → #13c
#14 · E2E proof: fresh-boot flow — grant TCC, toggle on, spawn 5 terminals, verify grid, drag-reorder —
  SPLIT by stoke-plan-14a.md brutal audit (verdict SPLIT-FURTHER) into #14a/#14b/#14c by PROVE-surface
  (automatable activate-to-grid / synthetic-CGEvent drag wiring / truly-human TCC+hardware; precedent
  #19→a/b, #12→a/b/c, #13→a/b/c).
#14a · Live E2E: real TilingActor.activate() tiles N real terminal windows to a grid (toggle's prod path) · DONE
  (2026-07-03: swift test 135/135 [+1 activateReenumeratesOverStaleCache] + invert-check red [flip activate→
  state.windows → 4 ✘, restored]; PROVEN LIVE on real WezTerm — the REAL TilingActor.activate() enumerated 5
  windows [single pid] and tiled them to a 3-column column-of-2 grid, readback origin-EXACT [dOrigin=0] with
  moved=true delta from birth [TRAP-15], lone 5th window full-height 560×1009, pending=15 [F8], PASS=true rc=0;
  screencapture docs/verification/task14a-activate-grid.png visually confirms the grid. LIVE INVERT [idempotent
  re-run → 0 pendings, moved=false → PASS=false rc=1] proves the guards aren't a rubber stamp. ZERO blast radius:
  targeted not-running WezTerm [pgrep-guarded], Bobby's iTerm2 verified 17→17. new AXProbe activatecheck mode +
  reseed/clearWrites fake helpers. Skeptic SPLIT-FURTHER [F1/F2 single-pid, F3 honesty-split, F4 invert-safety,
  F5 settle, F7 single-display — all folded]. Hit TRAP-19 [PAI hook blocks ~/.claude path in Bash → afplay cues
  directly]. Plan: stoke-plan-14a.md; receipt: receipt.md Row 8; verification: docs/verification/task14a-activate-grid.md.)
  blocked-by #11, #13a, #19b (ALL DONE). The FIRST live exercise of the production activate() path
  (enumerate-as-truth → TileEngine.retileCommands → pending-ledger apply) — closes #12c's "live activate
  INERT" gap and #19a's "never a global activate()" gap. Unattended under terminal-attributed AX trust,
  NO human/network/mouse. Live-proved against WezTerm (installed, NOT running → 0 windows → zero blast
  radius to Bobby's running iTerm2; single-pid multi-window via `wezterm cli spawn`, F1). Red-first swift
  test: activate re-enumerates over a stale cache. Plan: .engine/state/stoke-plan-14a.md.
#14b · Drag-reorder wiring: CGEventTap mouse-up → TilingActor.handleDragEnd + synthetic-CGEvent live prove · DONE
  (2026-07-03: swift test 140/140 green [+5 — 2 windowID(at:) discriminating hit-test, 3 DragMonitor
  click-vs-drag gate] + TWO invert-checks red [pick-windows[0] reddens the NON-first hit-test; remove the
  travel-gate reddens the click test; restored]; PROVEN LIVE on real WezTerm — AXProbe `dragcheck` posted a
  synthetic mouse-down→drag→up RECEIVED by the REAL TermTileKit.DragMonitor's own in-process session tap [A1],
  which resolved the dragged id at mouse-DOWN via windowID(at:) [tap-delivered (435,61)==posted, A2 no flip]
  and fired handleDragEnd [the ZERO-caller path] → a REAL AX reorder moving window 80801 slot0→slot2, grid
  shuffled to [80798,80795,80801,80791], ALL readbacks dOrigin=0, PASS=true rc=0; LIVE-INVERT [synthetic CLICK
  → travel-gate ate it, fired=false, ZERO reorder] PASS=true proves the tap isn't a rubber stamp. Zero blast
  radius: not-running WezTerm [pgrep-guarded], iTerm2 17→17. windowID(at:) [Kit, B1 down-identity] + DragMonitor
  [Kit, @convention(c) tap via userInfo, travel-gate B2, live-only surface] land; core-purity + all 10 checks
  PASS. Skeptic BLOCK→SAFE-WITH-FIXES [B1 mouse-DOWN identity, B2 click-gate, B3 discriminating test, M4 run()-
  freshness honesty, M5 blast radius, m6 A2-known, m7 sync-pump — ALL folded]. Fixed 2 probe flaws mid-prove
  [TRAP-20 stray-armed-tap-poll, TRAP-21 stale-cache birth-frames after activate w/o run()]. Plan:
  .engine/state/stoke-plan-14b.md; receipt: receipt.md Row 8; verification: docs/verification/task14b-drag-reorder.md.)
  blocked-by #11, #19b, #14a (ALL DONE). Built the MISSING production wiring (handleDragEnd had ZERO callers —
  TilingActor.swift:60). NOT a human DEP (skeptic F3 corrected the mislabel).
  DEFERRED to #14c: A3 [synthetic titlebar drag PHYSICALLY moves a window as sole cache driver] + the run()→
  echo-folding cache-freshness chain [load-bearing for BOTH drag identity and drop point; this beat feeds tiled
  frames deterministically] + SwiftUI-app embedding of run()+DragMonitor across the VM actor-rebuild lifecycle
  [DEP: blocked-by #14c — real drag physics + hardware + the run()/live-event lifecycle the VM defers need a bundled .app + human] → #14c
#14c · Fresh-boot human E2E: real .app System-Settings TCC grant + hardware drag + manual-tile-resist · S0
  blocked-by #14a, #14b, #13a. Also owns spike-07 manual-tile-resistance UNVERIFIED (human-in-loop).
  [DEP: external — a SIP-protected System-Settings Accessibility grant of the ad-hoc .app (cdhash UI click,
  spike-02) + a physical human at the machine for a real mouse drag + a manual native-tile gesture; none
  possible in an unattended/no-focus loop beat] → #14c

## Phase C — deferred (do not pull forward without a reason)

#15 · Multi-display + Spaces awareness · S0
  [DEP: shape — needs #19b's live engine surface; also owns the multi-display AXGeometry flip
  reference (#19a uses the single origin screen)]
#16 · Sparkle auto-updates + release pipeline · DONE
  (2026-07-03: stock SPUStandardUpdaterController + signed appcast; v0.1.0 released end-to-end —
  build/test/lint green in CI, 3 assets published, checksum verified, downloaded app launches,
  appcast resolves at SUFeedURL. Notarization deferred to Developer-ID decision.)
#17 · Gap/padding settings UI + per-app profiles · SPLIT into #17a (gap-size setting) / #17b (per-app profiles)
#17a · Gap-size setting: persisted AppSettings.gap + menu Stepper · DONE
  (2026-07-03: gap graduated from injected seam to loaded user-state [Option A; B was broken — root re-passes
  hardcoded 8]; clamp 0...40 both read+write via one clampedGap authority; default 8 upgrade-safe. Two plan
  audits + impl review [load-path clamp hole fixed]. Red-first, 2 invert-checks + load-clamp invert; Stepper
  render-validated. 166/166 tests.)
#17b · Per-app tiling profiles (gap/target per app) · S0
  [DEP: shape — pairs with the Settings window #24; defer until multiple apps + more per-app config exist]
  [DEP: shape — pairs with the Settings window (#24) once options exceed the inline menu]

## Phase D — menu-bar utility completeness (from docs/research/menubar-app-features-research.md)

#21 · About panel: version + what-it-is + links (site/GitHub/license) · DONE
  (2026-07-03: AppInfo authority #21a + About row #21b + Uninstall wiring #21c; render-validated via
  TERMTILE_GALLERY; code-reviewed plan+impl.)
  MUST-HAVE. Every surveyed utility ships one. Copy RememBar's AboutPopover shape (an ⓘ control →
  panel; ellipsis reveals Check-for-Updates + Uninstall). Version from CFBundleShortVersionString.
#22 · Uninstall: clean self-removal (trash bundle + deregister login item + clear owned paths) · DONE
  (2026-07-03: OwnedPaths #22a + Uninstaller + SettingsStore.purge #22b; #22c uninstall UI absorbed into
  #21's About panel. Scope-safety invert-checked; twice code-reviewed.)
  MUST-HAVE for a non-App-Store app. Template: RememBar's RememBarUninstaller — trash the .app, unregister
  the SMAppService login item, trash ONLY owned paths (~/Library/Application Support/TermTile,
  Preferences/dev.ecn.apps.termtile.plist, Caches/dev.ecn.apps.termtile), EXACT-match never glob (a
  neighbour dir must never be caught; make the trash op injectable so a test proves scope). CANNOT
  revoke the TCC grant — guide the user (System Settings toggle / `sudo tccutil reset Accessibility
  dev.ecn.apps.termtile`). Verify tccutil syntax vs the shipping macOS.
#23 · Accessibility trust-state UX: grant-break-aware fix-it row (3-state) · DONE
  (2026-07-03: AppSettings.wasTrusted + AccessibilityState + VM syncTrust/accessibilityState; onboarding
  window dropped as YAGNI. Two plan BLOCKERs (persist-clobber, latch-misses-trusted-at-launch) caught
  + fixed; runtime-revoke pinned; grant-broken copy render-validated (TERMTILE_GALLERY_BROKEN).)
  MUST-HAVE (whole app is grant-gated; the menu-bar icon can be hidden by Ice/Bartender). First launch:
  what-it-is → grant Accessibility (deep link) → find the icon. Also handle the verified grant-break:
  detect "untrusted but a TCC row exists" (moved/duplicate bundle) and warn/offer a fix.
#24 · Settings window (Cmd-,): tabbed General + Shortcuts once options exceed the inline menu · S0
  [DEP: shape — warranted only once #15 (multi-display) / #17 (gap/padding) add real config; Rectangle
  precedent. Defer until there's enough to configure; move config out of the inline menu then.]

#25 · Global hotkey to trigger Rearrange now · DONE
  (2026-07-03: Carbon RegisterEventHotKey HotKeyMonitor [mirrors DragMonitor C-bridge] → default ⌃⌥⌘R
  fires the existing rearrangeNow(); no AX grant needed; ID-matched dispatch. Impl review [Carbon correct +
  leak-free; deinit + eventNotHandledErr fixes]. Red-first + LIVE-PROVEN [real bundle registered=true,
  synthetic ⌃⌥⌘R routed through the real handler + fired, zero blast]. 170/170. Configurable combo → #24.)
#20 · Live CI verification: check/semgrep/release workflows execute green on GitHub Actions · DONE
  (2026-07-03: fixed main→master trigger bug; Check run 28633905044 success (swift test on macos-15),
  Semgrep run 28633905055 success — both on real master push. Release fires on first v* tag → #16.)
  blocked-by #13b. The #13b workflows are authored + locally static-validated (swift test + swiftlint
  proven green on this repo; YAML well-formed via ruby); this task PROVES them on real runners: check.yml
  green on a PR, semgrep.yml clean, and a `v*` tag drives release.yml (build-app.sh → attest → VirusTotal
  → gh release) with `secrets.VIRUSTOTAL_API_KEY` configured. Also run actionlint/yamllint for GH-Actions
  schema validation (absent locally in the loop). Needs #13c's signing identity for a shippable release.
  [DEP: external — requires GitHub runners + a push + configured repo secrets, none available in a no-network/no-push loop beat] → #20
