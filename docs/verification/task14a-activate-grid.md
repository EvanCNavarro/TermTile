# Task #14a — LIVE E2E: real `TilingActor.activate()` tiles N real windows to a grid

**Date:** 2026-07-03 · **Branch:** loop/phase-a · **PROVE-surface:** live macOS AX + real terminal windows

## What this proves (FL-1)

The FIRST live exercise of the **production toggle path** — `TilingActor.activate(config:)`
(`Sources/TermTileKit/TilingActor.swift:36-41`): `system.tileableWindows()` (enumerate-as-truth)
→ `TileEngine.retileCommands` → `apply` (size→pos→size per window, recording the pending ledger).

Distinct from prior live beats:
- **#19a** drove `adapter.writeFrame` DIRECTLY on precomputed frames — it never called `activate()`,
  so the enumerate-as-truth → retileCommands → ledger pipeline was never live-exercised.
- **#19b** drove only the single-window `.created` incremental path via `events()`.
- **#12c**'s live `activate()` was INERT (non-running target app → zero windows moved).

## Safety — zero blast radius to Bobby's windows

`activate()` tiles ALL of the target app's windows. Targeting Bobby's **running iTerm2** (17 windows)
would move them. Instead the prove targets **WezTerm**, which was **not running** before the beat
(`pgrep -x wezterm-gui` empty) — so every window under WezTerm's pid is a throwaway we created, and
`activate()`'s global tile touches nothing of Bobby's. Verified after cleanup: WezTerm gone, **iTerm2
still 17 windows** (untouched).

Single-process, many-windows (skeptic F1/F2): `open -a WezTerm.app` (1 window) + `wezterm cli spawn
--new-window` ×4 — all 5 under ONE pid, so the adapter (`NSRunningApplication…​.first`) enumerates all 5.

## Evidence — GREEN run (`activatecheck com.github.wez.wezterm 5`)

Origin screen AX visibleFrame `(0,38 1728×1033)`, gap 12. Enumerated exactly **5** windows.
`actor.activate()` → 5-window 3-column column-of-2 grid, every readback origin-EXACT:

| id | birth | target | readback | dOrigin | dSize | moved |
|---|---|---|---|---|---|---|
| 80708 | (116,168 574×453) | (12,50 560×498) | (12,50 560×498) | 0 | 0 | ✓ |
| 80705 | (87,139 574×453) | (12,560 560×498) | (12,561 560×498) | 0 | 0 | ✓ |
| 80702 | (58,110 574×453) | (584,50 560×498) | (584,50 560×498) | 0 | 0 | ✓ |
| 80699 | (29,81 574×453) | (584,560 560×498) | (584,561 560×498) | 0 | 0 | ✓ |
| 80695 | (0,52 574×453) | (1156,50 560×**1009**) | (1156,50 560×**1009**) | 0 | 0 | ✓ |

- `pending=15` (5 windows × size→pos→size trio) — the ledger populated correctly (F8).
- The lone 5th window (odd count) is correctly **full-height** (560×1009) in its own column.
- Every window **moved** from its scattered birth frame (574×453) → a real snap, not a coincidence
  with the pre-action state (TRAP-15 delta guard).
- `screencapture rc=0` → `docs/verification/task14a-activate-grid.png` (visually confirms the grid:
  col1 = 2 stacked, col2 = 2 stacked, col3 = 1 full-height). `PASS=true`, rc=0.

## Evidence — INVERT-check (anti-rubber-stamp, TRAP-15)

Re-ran `activatecheck` on the already-tiled windows. `activate()` is idempotent → the retile no-op
filter emits 0 commands → **0 writes, 0 pendings**; readback == birth → `moved=false` for all 5:
- `pending=0 (expect 15) ledgerOK=false`, every window `moved=false ok=false`, `PASS=false`, rc=1.

This proves the live assertion is NOT a rubber stamp: when `activate()` produces no real window
movement, the delta guard (`moved`) AND the ledger guard both fail the prove. (The invert flips the
observed EFFECT, never retargets a running app — F4.)

## Red-first unit test (`swift test`)

`TilingActorTests.activateReenumeratesOverStaleCache` — `activate()` re-enumerates
`system.tileableWindows()` as source of truth: after the window SET changes out from under the cache,
a second `activate` tiles the CURRENT windows `{3,4,5}` and replaces the stale `{1,2}`. INVERT
(`activate` uses `state.windows`): the first activate reads the empty fresh cache → tiles nothing →
the `[1,2]` assertion reds (4 issues, captured verbatim, restored). Full suite **135/135**.

## Scope boundary

#14a proves the enumerate→retile→write half of the toggle path. The echo-drain / `.internal`
classification (ADR rule-3 loop break) is #19b's `livecheck-events` surface — `activatecheck` runs no
event stream, so the recorded pendings TTL-expire (matches production, which does not run `run()` from
`activatecheck`'s composition). The remaining #14 work: **#14b** (CGEventTap→`handleDragEnd` wiring +
synthetic-CGEvent drag prove) and **#14c** (truly human: real `.app` System-Settings TCC grant +
hardware drag + manual-tile-resistance).
