# ADR 0001 — Functional core, imperative shell, compiler-enforced boundaries

Status: accepted (2026-07-02). Binding for all Phase B tasks (#8–#14). Loop beats MUST
follow this structure; deviations require a new ADR.

## Context

TermTile mixes pure geometry (layout math) with the messiest side-effect surface on
macOS (AX control of other apps' windows). Test discipline (red-first, no monkeypatching)
requires the interesting logic to be testable with plain values, and Swift 6 strict
concurrency requires a deliberate answer for CFRunLoop-based AXObserver callbacks.
RememBar validated the ingredient patterns in-house: pure-enum geometry
(MenuBarWindowPlacement), protocol seams + test doubles, injected dependencies.

## Decision

### Target graph (dependency direction enforced by SPM)

```
TermTileCore   (library)  — pure: layout math, domain types, reducer. CoreGraphics
                            geometry types only. NO AppKit / ApplicationServices.
TermTileKit    (library)  — depends on Core. The port (WindowSystem protocol +
                            WindowEvent/FrameCommand types), the AX adapter (the ONLY
                            code importing ApplicationServices for control), the
                            TilingActor, the fake WindowSystem for tests.
TermTile       (executable) — depends on Kit. Thin shell: MenuBarExtra UI, settings,
                            composition root (the only place production wiring happens).
AXProbe        (executable) — throwaway spike code, quarantined. Durable learnings get
                            promoted into tested Kit/Core modules (as already done for
                            WindowFiltering, AccessibilityTrust — these MOVE into Kit).
```

Fail-closed check (`.engine/checks/core-purity.sh`): non-zero iff any file under
`Sources/TermTileCore/` imports AppKit or ApplicationServices.

### The four rules

1. **Pure core.** `TileLayout.frames(count:visibleFrame:gap:) -> [CGRect]` and the
   engine reducer `reduce(State, WindowEvent) -> (State, [FrameCommand])` are pure
   functions in Core. All tiling decisions (which window goes to which slot, what
   happens on create/destroy/drag-end) are reducer logic — testable with plain values,
   no mocks.

2. **One port.** All window-system access goes through `WindowSystem` (enumerate,
   read frame, write frame, `AsyncStream<WindowEvent>` events). Production adapter =
   AX (with Rectangle's workarounds: size→position→size, AXEnhancedUserInterface
   disable, reduced messaging timeout). Test adapter = in-memory fake that simulates
   observed iTerm2 behavior (spike 03: tabs = one window; minimized stay enumerable
   with real frames; ids = CGWindowID).

3. **Self-move classification is data, not a flag.** FrameCommands register pending
   expectations (CGWindowID → expected frame + deadline). Incoming move events are
   matched (frame ± epsilon, within deadline) and classified internal/external by a
   pure function in Core. Only external moves feed drag detection.

4. **One actor owns AX.** A single `TilingActor` in Kit holds the adapter, the cached
   window snapshot (reads never block on AX), and serializes writes. The CFRunLoop
   AXObserver callback is bridged ONCE at the adapter into the AsyncStream; no AX
   callbacks anywhere else.

## Consequences

- #8 (layout math) lands in TermTileCore with property tests — no AX dependency.
- #9 (window state model) = the reducer + expectation ledger in Core, cache in Kit's
  actor. Swindler is a pattern reference only, never a dependency.
- #10/#11 (engine, drag-reorder) = reducer cases + adapter wiring; PROVE against live
  iTerm2 windows remains mandatory (FL-1) — the fake never substitutes for Row 8.
- #12 (shell) = composition root only; no business logic in SwiftUI views.
- Existing `Sources/TermTile/*.swift` (AppIdentity, WindowFiltering, AccessibilityTrust)
  migrate into the new targets as part of #8's first Phase B beat (smallest safe step:
  create targets, move files, fix imports, tests stay green).
- What we deliberately did NOT add (YAGNI): layout-strategy plugins (one layout exists),
  multi-app orchestration, config file formats. A second layout or target-app profile
  triggers the abstraction, not before.
