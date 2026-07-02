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
#3 · Spike: enumerate iTerm2 windows (AXUIElementCreateApplication → kAXWindowsAttribute) · S0
  blocked-by #2. Findings: do tabs present as one AXWindow? window IDs via
  _AXUIElementGetWindow? minimized/fullscreen filtering (kAXMinimizedAttribute,
  AXSubrole standard-vs-panel)?
#4 · Spike: set one iTerm2 window frame (size→position→size, AXEnhancedUserInterface off) · S0
  blocked-by #3. Findings: does iTerm2 honor kAXPosition/kAXSize promptly? min-size
  clamping? latency per write? Repeat probe on WezTerm for parity (app-agnostic goal).
#5 · Spike: AXObserver per-pid — windowCreated/moved/destroyed events for iTerm2 · S0
  blocked-by #3. Findings: event latency/ordering; kAXUIElementDestroyed per-window
  registration; CFRunLoop→Swift 6 strict-concurrency bridging (dedicated run-loop thread?).
#6 · Spike: drag-end detection — debounced kAXMoved vs CGEventTap/NSEvent global mouse-up · S0
  blocked-by #5. Read Rectangle + Amethyst source first (Trace), then probe both; pick
  with evidence. Also verify self-move tagging (ignore our own AX writes).
#7 · Spike: macOS native tiling interference — AX frame sets vs Sequoia/Tahoe snap · S0
  blocked-by #4. Findings: does native tiling fight programmatic frames; per-app or
  global suppression options.

## Phase B — the informed build (unblocked by Phase A evidence)

#8 · Layout math: pure module — (windowCount, visibleFrame, gaps) → column-of-2 frames · S1
  blocked-by #1 only (pure function, no AX). columns=ceil(N/2), even widths, last column
  1 window if N odd; property tests across N=1..12 + edge frames. TDD showcase task.
#9 · Window state model: cached AX snapshot + self-move tagging (Swindler pattern) · S0
  blocked-by #3, #5. Instant reads from cache; async writes; `external` flag on moves;
  reduced AX messaging timeout (~1s).
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
