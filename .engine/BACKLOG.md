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
#7 · Spike: macOS native tiling interference — AX frame sets vs Sequoia/Tahoe snap · S0
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
#9 · Window state model: reducer + expectation ledger (ADR-0001 rules 3-4) · S0
  blocked-by #3, #5, #8 (needs the target split). Pure reducer (State, WindowEvent) →
  (State, [FrameCommand]) in Core; pending-expectation ledger (CGWindowID → frame ±
  epsilon + deadline) classifies moves internal/external as a pure function; TilingActor
  in Kit owns the AX adapter + cached snapshot (instant reads, serialized async writes,
  ~1s AX messaging timeout). Swindler = pattern reference only, never a dependency.
#10 · Tiling engine: toggle-on retile + auto-retile on create/destroy · S0
  blocked-by #4, #5, #8, #9. PROVE: live iTerm2 windows snap to grid on toggle and on
  new-window; screencapture evidence.
#11 · Drag snap-reorder: nearest-slot assignment on drag end + shuffle · S0
  blocked-by #6, #10.
#12 · Menu-bar app shell: toggle, target-app picker, launch-at-login, settings · S0
  blocked-by #1; UI wiring to engine blocked-by #10. SwiftUI MenuBarExtra `.window` style
  (RememBar pattern; delegate-adaptor gotcha: init() is the reliable hook). Launch-at-login
  via SMAppService.mainApp (RememBar lacks this — audit §8.6). Settings = UserDefaults
  behind a small protocol (audit §8.7). Permission UX: probe + Privacy_Accessibility deep
  link + blocked-status fix-it row (adapt FileSearchAccessChecker pattern). Includes live
  prompt-path UX observation from the bundled-app identity (spike 02: prompt can't fire
  from a pre-trusted shell; bundle probing pollutes TCC).
#13 · Packaging + CI: .app bundle, codesign, smoke scripts, test/release workflows · S0
  blocked-by #12. Authority: docs/research/remembar-audit.md COPY/ADAPT table. Build script
  (Info.plist heredoc, LSUIElement, sips/iconutil icon; glob resources — audit §8.4),
  inside-out ad-hoc codesign no --deep + verify strict, test-packaged-app.sh launch proof,
  monotonic build number (NOT dots-stripped — audit §8.5), SwiftLint + Semgrep + Dependabot,
  release.yml with VirusTotal + provenance attestation + SHA-256 ("virus testing"), AND
  swift test in CI gating release (RememBar's biggest gap — audit §8.1-8.3). Includes a
  stable signing identity (Developer ID or self-created cert) so .app TCC grants survive
  rebuilds (spike 02 proved ad-hoc cdhash pinning voids grants; required before #14).
#14 · E2E proof: fresh-boot flow — grant TCC, toggle on, spawn 5 terminals, verify grid, drag-reorder · S0
  blocked-by #11, #13. Recorded evidence (screencaptures) into docs/verification/.

## Phase C — deferred (do not pull forward without a reason)

#15 · Multi-display + Spaces awareness · S0
  [DEP: shape — needs #10's engine surface]
#16 · Sparkle auto-updates + release pipeline · S0
  [DEP: blocked-by #13]
#17 · Gap/padding settings UI + per-app profiles · S0
  [DEP: shape — post-MVP polish]
