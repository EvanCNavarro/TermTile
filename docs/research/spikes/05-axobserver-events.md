# Spike 05 — AXObserver per-pid window events: iTerm2 (task #5)

Observed on: Apple Swift 6.0.3, macOS 15.1 (24B83), arm64, iTerm2 pid 12953.
Probe: `Sources/AXProbe/main.swift` `observe <bundle-id> <seconds> [--no-perwin]` mode
(throwaway-quality, committed); durable tested code: `Sources/TermTile/WindowEvent.swift`
(`WindowEventKind` AX-notification-name mapping, inlined into the probe — executables
can't import executables, spike-04 precedent). Three full lifecycles (n=3, FL-6): create
window via AppleScript → 3× setframe battery (size→pos→size, spike-04 mode) → close.
All mutations only on spike-created windows (78240, 78244, 78247); baseline window-ID
SET verified identical afterward (15 ids, set-compare not count — audit F8).

## Questions → observed answers

### (a) Which notifications fire from APP-element registration, and in what order?
ALL FOUR registered names fire from app-element registration alone: `AXWindowCreated`,
`AXWindowMoved`, `AXWindowResized`, **and `AXUIElementDestroyed`** (see (b)). All
registrations return err=0 (app-level and per-window; duplicate add = -25209 benign).
Ordering was strictly consistent across all 3 lifecycles, matching action order:
created → (resized → moved)×3 → destroyed. Within a battery, resized precedes moved,
matching the size-before-position write order. No reordering ever observed.

```
event: epochUs=1782994037977593 name=AXWindowCreated kind=created id=78247 idErr=0 hash=1685037960
event: epochUs=1782994039159378 name=AXWindowResized kind=resized id=78247 idErr=0 hash=1685037960
event: epochUs=1782994039160080 name=AXWindowMoved kind=moved id=78247 idErr=0 hash=1685037960
...
event: epochUs=1782994040658881 name=AXUIElementDestroyed kind=destroyed id=0 idErr=-25201 hash=1685037960
```

### (b) Is per-window kAXUIElementDestroyed registration required? → NO (on iTerm2/15.1).
CONTRADICTS the research doc (:23-24 "register kAXUIElementDestroyed per-window"):
run 3 suppressed ALL per-window registration (`--no-perwin`) and the spike window's
destroyed event still fired from the app-element registration alone. App-level
registration accepts silently (err=0 — registration error can never answer this; only
fire/no-fire does). Dual registration (app + per-window, runs 1-2) produced NO
duplicate for the spike window. CAVEAT: this is one app on one OS build; per-window
registration stays the belt-and-braces default for #9 since it costs one call per
window and dedupe-by-hash is needed anyway (see anomaly).

### (c) Event latency? → moved/resized ≈ 6–14 ms after the write; create/destroy
≈ 200–290 ms spawn-inclusive UPPER BOUNDS (osascript ≈ 40ms+ inside the bound; the
event consistently arrived ~100–220ms BEFORE the driving osascript even returned, so
true AX delivery is far below the bound).
- created (pre-create shell stamp → event): 287 / 257 / 254 ms (n=3, osascript spawn
  + window construction included).
- resized (in-process size1 write stamp → event): 11.7–13.8 ms (n=9 batteries).
- moved (in-process pos write stamp → event): 6.5–8.3 ms (n=8; run-1 battery 1 had no
  position change → NO moved event fired).
- destroyed (pre-close shell stamp → event): 198 / 194 / 195 ms (n=3, osascript-inclusive).
Consequence: event-driven retile (#10) has a comfortable latency budget; AX delivery
is same-order as the writes themselves (<15ms in-process to in-process).

### (d) CFRunLoop → Swift 6 bridging? → the naive shape compiles and works; no
dedicated thread machinery needed for a probe.
`@preconcurrency import ApplicationServices`; a NO-CAPTURE closure literal converts to
the `@convention(c)` `AXObserverCallback`; the callback receives the AXObserver as its
first parameter, so on-the-fly re-registration needs no globals/refcon.
`AXObserverGetRunLoopSource` → `CFRunLoopAddSource(CFRunLoopGetCurrent(), …, .defaultMode)`
→ `CFRunLoopRunInMode(.defaultMode, deadline, false)` (returns rc=3
kCFRunLoopRunTimedOut on the deadline path). Compiles clean under `-swift-version 6`,
zero diagnostics (audit F1 verified strict checking is active via control test). For
#9's TilingActor the open question shrinks to: which thread's run loop hosts the
source (main-thread hosting worked here; callbacks arrived on it).

### (e) Coalescing: 3 writes (size→pos→size) → exactly 1 resized + 1 moved.
Events fire on ACTUAL change only: the no-op size2 write never produced a second
resized; an unchanged position produced no moved. iTerm2 coalesces the write batch
into one notification per changed attribute.

## Operational facts (probe engineering, verified)
- Swift `print()` to a redirected file is FULLY buffered — a killed process loses the
  ENTIRE log (verified: 0 bytes after kill -9). `setvbuf(stdout, nil, _IOLBF, 0)` at
  mode start makes it line-buffered/tail-able (audit F4). Mandatory for any long-running
  logging probe.
- macOS shell cannot stamp sub-second epoch (`date +%s%N` prints a literal `N`); use
  python3/perl. In-process stamps (`Date().timeIntervalSince1970`, tracks CLOCK_REALTIME
  within ~1µs) wherever latency claims matter — shell spawn overhead (osascript ≈40ms,
  AXProbe ≈121ms) swamps AX latencies (audit F5).
- `_AXUIElementGetWindow` on a destroyed element fails with **-25201
  kAXErrorInvalidUIElement, id=0** — the CGWindowID is UNRESOLVABLE at destroy time.
  `CFHash(element)` remains stable dead-or-alive and correlates create↔destroy.
- Two AX clients (observer process + setframe process) ran concurrently with zero
  interference (assumption A6 confirmed).
- Unknown argv falls through to AXProbe's trust-report mode and exits 0 — drivers must
  verify observe-mode OUTPUT lines, never exit code alone (audit F7).

## Anomaly log (honest record)
In runs 2 AND 3, a second `AXUIElementDestroyed` fired for an element hash NEVER seen
as a window, at a reproducible ~4.97s after the window close (955.245−950.273 and
045.635−040.659). Baseline window set was intact both times. Best explanation: iTerm2
retains the closed session ~5s for "undo close", then destroys the retained element;
app-level destroyed registration reports it. NOT investigated further (out of scope);
recorded because #9 must tolerate destroy events for elements it never tracked.

## Consequences for the build
- #9 state model: maintain an element(hash)→CGWindowID map from create/enumerate time —
  ids are unresolvable at destroy (-25201). IGNORE destroys whose hash is unknown (the
  ~5s-retention anomaly proves they occur). Dedupe destroys by hash. Event vocabulary =
  `WindowEventKind` (tested, Sources/TermTile/WindowEvent.swift).
- #9/#10: register app-level created/moved/resized (+destroyed as backstop) once per
  pid; per-window destroyed registration on create is cheap belt-and-braces (-25209
  benign on duplicates). No dedicated observer thread required for correctness; run-loop
  hosting decision (main vs dedicated) deferred to #9's TilingActor design with the
  working shape recorded above.
- #6 drag detection: programmatic AX writes DO fire moved/resized (~6-14ms); the
  self-move tagging problem is real (research :47-50 Swindler pattern confirmed
  empirically) — #6's debounce probe can reuse this observe mode as-is.
- #10 latency budget: event→retile reaction can assume <15ms delivery for AX-initiated
  changes; create/destroy delivery beats even the AppleScript round-trip that caused it.

## UNVERIFIED edges (explicit)
- Per-window-required destroyed behavior on OTHER apps (WezTerm etc.) — (b)'s answer is
  iTerm2/macOS 15.1 only; parity check belongs to the app-agnostic pass.
- Human-drag moved-event cadence (continuous vs drag-end) — that is #6's question.
- Callback thread under a DEDICATED run-loop thread (only main-thread hosting observed).
- n=3 lifecycles for created/destroyed latency (n=8-9 for moved/resized).
