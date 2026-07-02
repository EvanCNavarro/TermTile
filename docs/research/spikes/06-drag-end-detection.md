# Spike 06 — drag-end detection + self-move tagging (task #6)

Observed on: Apple Swift 6.0.3, macOS 15.1 (24B83), arm64, iTerm2 pid 12953, spike window
78924. Probe: `Sources/AXProbe/main.swift` `dragprobe <bundle-id> <windowID>` +
`mouseprobe <seconds>` modes (throwaway-quality, committed). Durable tested code:
`Sources/TermTileCore/MoveClassifier.swift` (`MoveClassifier`/`PendingMove`/`MoveOrigin`,
12 tests) — imported LIVE by the probe (AXProbe now depends on TermTileCore), so the live
proof exercises the REAL shipping classifier, not an inline copy.

Reference-source caveat (honest): this beat had **no network access** and Rectangle/Amethyst
source is not vendored, so their exact drag-end code could not be read this beat. The in-repo
authority used is `docs/research/macos-tiling-research.md:47-62,78-79` — a prior verified
line-by-line distillation of Rectangle's `AccessibilityElement.swift` and the Swindler
`external`-flag pattern. The mechanism call below is therefore a **reasoned recommendation**
grounded in that authority + spike-05 cadence data + a live feasibility probe — NOT an A/B
decision proven by capturing a real human drag this beat (see UNVERIFIED).

## The two questions #11 (drag snap-reorder) inherits

### Q1 — Self-move tagging: don't treat our own AX writes as user drags. → SOLVED (live).
spike-05 proved the tiler's own frame writes fire `AXWindowMoved`/`AXWindowResized`
(~6-14 ms). `MoveClassifier` is a pure classifier over a pending-expectation ledger
(Swindler's `external` pattern, research :47-51): a frame change is `.internal` iff some
NON-EXPIRED pending move for that window id matches the observed frame within epsilon
(reusing `FrameMath.approximatelyEqual`), else `.external`.

Live proof (`dragprobe`, exit 0 — gated on a REAL moved event firing, not a ledger-only
verdict; audit B1):
```
dragprobe: placed base, preMove=(200,200 800x600)
dragprobe: expect=(280,280 800x600) armed epochUs=1782999701361261
event: name=AXWindowMoved id=78924 epochUs=1782999701363134
dragprobe: movedFired=true posChanged=true observed=(280,280 800x600)
dragprobe: verdict vsExpected=internal vsEmpty=external vsShifted+100=external
dragprobe: PASS=true
```
On the SAME real AX-delivered frame (~1.9 ms from arm to event), the REAL classifier tags
it `.internal` against the recorded expectation, `.external` against an empty ledger, and
`.external` against a +100-shifted ledger — discrimination is purely ledger-driven on real
data. Baseline 15-window set verified identical after (spike window 78924 gone, no leak).

**LEDGER CONTRACT (audit B2 — the load-bearing subtlety).** A single `size→pos→size` tiler
write emits SEPARATE `resized` + `moved` notifications (spike-05 §e), and under the async
write dispatch the real tiler will use (research :41-45) the `resized` echo can carry an
INTERMEDIATE `(newSize, oldPos)` frame. Against ONLY a final-frame expectation that echo
classifies `.external` — the exact feedback loop #6 exists to prevent. The synchronous spike
hides this (all three writes land before the run loop processes either notification).
Resolution: the classifier stays a dumb "match ANY non-expired pending for this window"; the
**caller (#9/#11 TilingActor) MUST record ONE `PendingMove` per AX write it issues** (not
just the final frame). Both directions are pinned by unit tests
(`intermediateVsFinalOnlyExternal` = the failure mode; `intermediateVsPerWriteLedgerInternal`
= the fix). This is the single most important consequence for #9/#11.

### Q2 — Drag-END signal: debounced kAXMoved vs global mouse-up. → RECOMMEND global mouse-up.
Reasoned recommendation (not reception-proven this beat):
- **Global mouse-up (CGEventTap) is cadence-independent** — it fires exactly ONCE per
  physical button release, a precise drag-END boundary regardless of how the app streams
  intermediate moves.
- **Debounced kAXMoved must GUESS a quiet-window timeout** against an unmeasured, app-specific
  cadence. spike-05 showed iTerm2 coalesces AX moved events app-side; a timeout tuned to one
  app need not hold app-agnostic. A slow drag with a mid-gesture pause false-triggers a
  debounce; mouse-up cannot.
- **Self-move tagging (Q1) is required either way** (our writes echo regardless of which
  drag-end signal is chosen), so `MoveClassifier` is the foundational deliverable independent
  of the A/B choice.

Feasibility probe (`mouseprobe`, non-prompting per audit N12):
```
mouseprobe: inputMonitoringPreflight=true
mouseprobe: listen-only leftMouseUp tap installed+enabled from bg process; watching 2s ...
mouseprobe: done
```
A listen-only `leftMouseUp` `CGEventTap` INSTALLS + ENABLES from the (terminal-attributed,
Input-Monitoring-granted) background process — the one real feasibility risk for a menu-bar
app clears. `CGPreflightListenEventAccess()` was used (never `CGRequestListenEventAccess`)
so no TCC dialog was raised on the unattended screen.

**Recommended #11 design:** global mouse-up (CGEventTap) as the drag-END trigger →
`kAXMoved` identifies WHICH window moved → `MoveClassifier` filters our own writes.
Debounced-kAXMoved is the fallback if the Input-Monitoring grant proves unacceptable UX.

## Consequences for the build
- **#9/#11**: use `MoveClassifier`; record a per-write `PendingMove` for EVERY AX write
  (intermediate + final), not just the final frame (B2 contract above). Deadline-bound each
  expectation (the probe used ~2 s); an expired expectation must NOT mask a later real drag
  (tested).
- **#12 permission UX**: the CGEventTap drag-end path needs an **Input Monitoring** TCC grant
  in addition to Accessibility (mouseprobe: preflight gates tap creation). Add an
  Input-Monitoring fix-it row alongside the Accessibility one. `CGPreflightListenEventAccess()`
  is the non-prompting status check; `CGRequestListenEventAccess()` is the prompt.
- **Coincidental-frame limitation (honest)**: a real user drag that happens to land within
  epsilon of a LIVE pending expectation classifies `.internal` (false negative). Inherent to
  frame-matching; the per-expectation deadline bounds the exposure window to ~the settle time.
  Documented, not fixed (out of scope for a pure classifier).

## UNVERIFIED edges (explicit)
- **Live HUMAN-drag `kAXMoved` cadence** (continuous stream vs drag-end-only) and **live
  mouse-up RECEPTION** — both require a physical drag / click, which an unattended loop cannot
  produce without injecting synthetic global input (declined for safety: risks disrupting
  Bobby + trips the local-control audio-cue rule). Manual repro for a human-in-loop session:
  run `AXProbe observe com.googlecode.iterm2 20` and drag a window by hand → inspect the
  `AXWindowMoved` line cadence; run `AXProbe mouseprobe 20` and release the mouse → expect a
  `leftMouseUp observed` line. The Q2 recommendation does not depend on these (cadence-
  independence is the argument FOR mouse-up).
- **CGEventTap reception when the menu-bar app is a bundled `.app`** (not a terminal-attributed
  shell exec) — Input-Monitoring attribution parity belongs to #12/#13's signed-bundle pass
  (cf. spike-02's TCC-attribution findings).
- Debounce timeout tuning across apps (WezTerm etc.) — app-agnostic pass.
