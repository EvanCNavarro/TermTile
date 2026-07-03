# Task #14b — LIVE: drag-reorder wiring (CGEventTap mouse-up → TilingActor.handleDragEnd)

**Date:** 2026-07-03 · **Branch:** loop/phase-a · **PROVE-surface:** live macOS session event tap +
synthetic CGEvent + real WezTerm windows

## What was built (the missing production wiring)
`TilingActor.handleDragEnd(_:)` had ZERO callers (TilingActor.swift:60). This beat added the caller:
- `TilingActor.windowID(at:)` (Kit) — resolves the dragged id at mouse-DOWN by hit-testing the cached
  snapshot (skeptic B1: at mouse-down the windows are still on their non-overlapping grid slots, so
  the cursor picks one unambiguously; resolving at mouse-UP would be ambiguous — the dragged window
  overlaps its drop target).
- `DragMonitor` (Kit) — the global left-button `CGEventTap`. Identity captured at mouse-DOWN; the
  drag-end action fires ONLY past a travel threshold (skeptic B2: a plain click never reorders).
  The tap plumbing is a live-only surface (like `AXWindowSystem`); its decision logic
  (`handleDown`/`handleUp`) is unit-tested without a tap.

## Unit evidence (swift test 140/140; +5 this beat)
- `windowID(at:)` — discriminating hit-test (queries a NON-first window → a "pick windows[0]" mutant
  reddens, invert-checked) + a gap → nil.
- `DragMonitor` — a real drag fires `onDragEnd` with the DOWN id; a click (below threshold) fires
  nothing; a drag over no window fires nothing. Invert (remove the travel-gate) → the click test reddens.

## LIVE evidence — `AXProbe dragcheck com.github.wez.wezterm 4`
Origin-screen AX visibleFrame `(0,38 1728×1033)`, gap 12, 4 throwaway WezTerm windows (WezTerm was
NOT running before the beat → every window under its pid is a throwaway; zero blast radius).

### DRAG (PASS=true, rc=0)
```
dragcheck: inputMonitoringPreflight=true axTrusted=true mode=drag
dragcheck: orderBefore=[80801, 80798, 80795, 80791] draggedID=80801
stage: post drag down=(435,61)
resolve: tap-delivered downPt=(435,61) → id=80801      # A1+A2: self-posted event reaches the in-process
onDragEnd: id=80801                                     # tap; delivered point == posted (no flip)
dragcheck: slot=0 id=80798 ... readback=(12,50 846x498)  dOrigin=0
dragcheck: slot=1 id=80795 ... readback=(12,561 846x498) dOrigin=0
dragcheck: slot=2 id=80801 ... readback=(870,50 846x498) dOrigin=0   # dragged 80801 landed at slot 2
dragcheck: slot=3 id=80791 ... readback=(870,561 846x498) dOrigin=0
dragcheck: finalOrder=[80798,80795,80801,80791] expect=[80798,80795,80801,80791]
           fired=true draggedFinalSlot=2 orderOK=true deltaOK=true readbackOK=true
dragcheck: PASS=true → docs/verification/task14b-drag-reorder.png
```
A real `leftMouseUp` posted by AXProbe was received by the REAL `DragMonitor` tap, which resolved the
dragged id at mouse-DOWN (`windowID(at:)`) and fired `handleDragEnd` → a REAL AX reorder+write moving
window 80801 from slot 0 to slot 2 (delta from birth slot, TRAP-15), the whole grid shuffling and every
window snapping origin-EXACT. Screencapture `task14b-drag-reorder.png` shows the clean 2×2 grid.

### INVERT — click is ignored (PASS=true, rc=0)
```
dragcheck: mode=INVERT(click)  ... post click down=(435,61)
resolve: tap-delivered downPt=(435,61) → id=80801       # tap still SEES the event...
dragcheck: finalOrder=[80801,80798,80795,80791] expect=[...unchanged...]
           fired=false draggedFinalSlot=0 orderOK=true deltaOK=true readbackOK=true
dragcheck: PASS=true
```
A synthetic CLICK (zero travel) reached the same tap but the travel-gate (B2) ate it: `fired=false`,
ZERO reorder, order unchanged. Proves the tap is not a rubber stamp AND the click≠drag gate live.

### Blast radius
`pgrep -x wezterm-gui` empty before; iTerm2 window count **17 → 17** (untouched); WezTerm killed after.

## Grounded facts (micro-probe folded into the prove)
- **A1 — self-posted events reach the in-process tap:** TRUE (`resolve`/`onDragEnd` fired from posted
  down/up).
- **A2 — CGEvent location space == AX top-left frame space:** TRUE, no flip (delivered `(435,61)` ==
  posted; resolved the slot-0 window on a single display).
- **A4 — terminal-attributed AXProbe may post synthetic events:** TRUE (`axTrusted=true`,
  `inputMonitoringPreflight=true`).

## What is NOT proven here (→ #14c)
- **A3 — a synthetic titlebar drag PHYSICALLY moves a window** as the SOLE cache driver. This prove
  feeds the drop point into the cache via an injected `.moved` (the mid-drag update `run()`'s echo
  stream delivers in production, or a hardware drag delivers). The reorder WRITE moves the real window;
  the physical-drag-moves-window physics is #14c (hardware drag).
- **The `run()`→echo-folding cache-freshness chain.** After `activate()` the actor cache holds BIRTH
  frames until `run()` folds the tiling echoes; this beat's probe feeds the tiled frames in
  deterministically (the run()→real-echo chain is #14c). This freshness is load-bearing for BOTH the
  drag identity (`windowID(at:)`) and the drop point.
- **SwiftUI-app embedding.** Starting `run()` + installing/tearing-down `DragMonitor` across the
  MenuBarViewModel actor-rebuild-on-target-switch lifecycle (VM deliberately defers `run()`,
  MenuBarViewModel.swift:13-16). Code-review-only + entangled with the deferred run() lifecycle → #14c.
