# Task #1 verification — SPM package skeleton (2026-07-02)

## Test evidence (red-first)

- Green baseline: `swift build` exit 0 ("Build complete!"); `swift test` exit 0 —
  `✔ Test run with 2 tests passed after 0.001 seconds.`
- Invert-check (real assertion red, not compile red): flipped the expected bundle ID to
  `dev.ecn.apps.WRONG` →
  `✘ ... Expectation failed: (AppIdentity.bundleID → "dev.ecn.apps.termtile") == "dev.ecn.apps.WRONG"`
  → restored → re-green (`✔ Test run with 2 tests passed`).
- Naming drift: `grep -rn BrowserMemoryBar Package.swift Sources Tests` → no matches.

## Live-surface PROVE (real launch, audio-cue wrapped)

Launched `.build/debug/TermTile` as a real process:

1. `PROCESS-ALIVE pid=38493` — app runs headless-launched without crashing.
2. AX (read-only, System Events): process "TermTile" owns a menu bar whose item is
   described as **"status menu"** — the MenuBarExtra status item registered with the
   window server.
3. CGWindowList: `FOUND-WINDOW id=77320 layer=25 bounds=[X:-4721, W:72, Y:0, H:37]` —
   layer 25 is NSStatusWindowLevel, i.e. a real status-bar item window, 72×37.

## Why the item is not visible in `task1-menubar-proof.png`

A menu-bar manager on this Mac (the "…" overflow chevron) relocates unknown new status
items off-screen (X = -4721). This is environmental, not an app defect: the status item
exists at status-bar window level and is AX-enumerable. Follow-up UX (making the item
discoverable/pinned) belongs to task #12 (menu-bar app shell).
