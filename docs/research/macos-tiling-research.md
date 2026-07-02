# TermTile — macOS Tiling Research (Deep Research, 2026-07-02)

Adversarially verified deep-research report (101 agents, 19 sources, 95 claims extracted,
24 confirmed / 1 refuted). Informs the TermTile architecture: a Swift menu-bar app that
rigidly auto-tiles one chosen app's windows (iTerm2/WezTerm) into even columns of 2, with
a global on/off toggle and snap-reorder on drag.

## Headline conclusions

1. **Nothing does this out of the box.** No built-in layout in Amethyst (xmonad-style
   main-pane), yabai (BSP), or AeroSpace (i3-style tree) implements a fixed
   rows-per-column grid (exactly 2 per column, columns growing with window count).
   Amethyst's beta JavaScript custom-layout API (`getFrameAssignments`) *could* express
   it; AeroSpace's 4 layouts cannot. Closest prior art for **per-app scoping** is the
   Hammerspoon **WindowScape** spoon (sryo/Spoons) — auto-tiles only allow-listed apps,
   retiles on open/close/move — but in Lua and without the 2-per-column layout.
   → TermTile is a real gap, and a *small* one to fill.

2. **Architecture: pure public Accessibility API. No SIP changes.** The
   AeroSpace/Amethyst approach: Accessibility TCC permission only.
   - `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute` to enumerate windows.
   - Per-application `AXObserver` (created per-pid via `AXObserverCreate`) for
     `kAXWindowCreated` / moved notifications; register `kAXUIElementDestroyedNotification`
     per-window. The system-wide AX element does NOT support notifications
     (`kAXErrorNotificationUnsupported`), so per-app observers + NSWorkspace launch
     notifications are the pattern all three major tilers use.
   - Window identity: private `_AXUIElementGetWindow` (the one private call AeroSpace
     allows itself) with a frame-vs-CGWindowList matching fallback (Rectangle's pattern).

3. **yabai's SIP story confirms the boundary.** SIP disable exists solely to inject a
   scripting addition into Dock.app (which holds the privileged WindowServer connection).
   SIP-gated features are compositor-level: window **animations**, transparency, spaces
   manipulation, layering. Core BSP tiling works with SIP fully enabled.

4. **"Smooth" animation is constrained.** Compositor-level animated window movement is
   impossible via AX alone (it's on yabai's SIP-gated list; AeroSpace/Amethyst ship
   without animations by design). Options for TermTile's snap-reorder feel:
   - Instant frame sets (what AeroSpace/Amethyst do) — crisp, reliable. **Recommended v1.**
   - Interpolated `AXPosition` loops (Hammerspoon-style) — notoriously janky; avoid.

5. **AX is synchronous IPC — architect around stalls.** Default messaging timeout is 6s;
   an unresponsive app can block a naive tiler for seconds. Proven mitigation (Swindler's
   design — reuse the *pattern*, not the dormant library): in-process cached state model
   for instant reads + async/concurrent dispatch of writes; reduce the AX messaging
   timeout (alt-tab-macos uses 1s).

6. **Feedback-loop safety for drag-reorder.** The tiler must tag its own AX moves so it
   doesn't treat them as user drags (Swindler's `external` flag pattern — its snap-to-grid
   example is literally this use case). Drag-end detection: debounce `kAXMoved`
   notifications and/or global mouse-up monitoring (NSEvent/CGEventTap) — open question
   below.

## Battle-tested AX pitfalls to copy from Rectangle (MIT, Swift)

Verified line-by-line in `Rectangle/AccessibilityElement.swift`:
- **size → position → size** ordering for cross-display moves (macOS clamps AX-set sizes
  to the window's current display).
- Disable the app-level **`AXEnhancedUserInterface`** attribute before programmatic
  resizes (it interferes), conditionally re-enable after.
- Window enumeration/matching: `_AXUIElementGetWindow` windowId with frame-equality
  fallback against `CGWindowListCopyWindowInfo`.

## Reference implementations

| Project | License | Relevance |
|---|---|---|
| Amethyst | MIT, ~98% Swift, active (2026-04) | Best architectural reference: AX-based Swift menu-bar tiler. Its Silica layer uses some private CGS calls for Spaces (no SIP needed). |
| Rectangle | MIT, Swift | The AX pitfall workarounds above. |
| AeroSpace | Public AX + one private call, no SIP | Proof the pure-AX architecture works; tree model not reusable. |
| Swindler | MIT, alpha, dormant since 2023-12 | Pattern donor only: cached state model, `external` event flag, ordered gap-filled events. |
| WindowScape (sryo/Spoons) | Lua/Hammerspoon | Per-app allow/deny-list scoping model. |

## Open questions (unresolved by research — resolve empirically during build)

1. **iTerm2 AX quirks** (biggest unverified area): do native tabs present as one AXWindow?
   Minimum window sizes? Does it honor `kAXPositionAttribute` writes promptly?
   → Probe empirically in a spike before committing layout math.
2. **Drag-end detection**: global mouse-up (CGEventTap/NSEvent) vs debounced `kAXMoved`
   streams — inspect Rectangle/Amethyst source for their approach.
3. **macOS Sequoia native tiling interaction**: does it fight AX-driven frame sets;
   per-app suppression? (Native tiling is manual-snap only — it can't do auto-layout —
   but may interfere.)
4. **Swift 6 strict concurrency**: bridging CFRunLoop-based AXObserver callbacks to actor
   isolation — may need a dedicated thread/run-loop wrapper.

## Caveats

- Rectangle Pro / Loop / Moom / Swish / Magnet / Stage Manager claims didn't survive
  verification — the manual-snap side of the landscape is under-documented here (and
  irrelevant to the auto-tiling goal).
- yabai's SIP-gated list grows over time; Sequoia/Tahoe keep changing SIP/TCC mechanics —
  re-verify against the current OS at build time.
- One refuted claim: "AX is the only supported mechanism and it's buggy" (1-2 vote) —
  don't overstate AX exclusivity.

## Sources (primary)

- https://github.com/ianyh/Amethyst
- https://github.com/nikitabobko/AeroSpace
- https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
- https://github.com/koekeishiya/yabai/issues/13
- https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift
- https://github.com/tmandry/Swindler
- https://github.com/sryo/Spoons
- https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification
