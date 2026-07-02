# Spike 04 — set one window frame: iTerm2 + WezTerm (task #4)

Observed on: Apple Swift 6.0.3, macOS 15.1 (24B83), arm64, SINGLE display (audit F8:
cross-display clamping — the rationale for size→position→size — unobservable here; the
ordering is kept anyway, Rectangle-verified). Probe: `Sources/AXProbe/main.swift`
`setframe <bundle-id> <cgwindowid> <x> <y> <w> <h>` mode (throwaway-quality, committed);
durable tested code: `Sources/TermTile/FrameMath.swift` (the ±epsilon comparator, inlined
into the probe because executable targets can't import executables — audit F4).
All writes were made ONLY to windows created by this spike (iTerm2 window 78164 via
AppleScript `create window with default profile`; WezTerm window 78184 via `open -a`).

## Questions → observed answers

### (a) Does iTerm2 honor kAXPosition/kAXSize writes promptly? → YES, exactly and fast.
`AXUIElementIsAttributeSettable` = true for both attributes on every window (including
minimized — audit F1). All 21 writes across both apps returned err=0. Readback matched
the request EXACTLY (integer-identical, epsilon never needed) on every non-clamped probe:

```
write: size1 err=0 us=6274
write: pos   err=0 us=7712
write: size2 err=0 us=23752
after: frame=100,100 800x600 stable=true settleMs=61 matchesRequest=true
```

Settle: the FIRST 50ms poll was already stable in all 11 batteries (settleMs 51–75,
which includes the fixed 50ms sleep → true settle is <50ms; the probe cannot resolve
finer). No async drift, no retry ever consumed.

### (b) Min-size clamping? → YES, silent clamp; floors are PER-APP.
Position is honored exactly while size clamps; writes still return err=0 — clamping is
only visible in readback (never trust a .success as "frame applied"):

| app | request | readback | floor |
|---|---|---|---|
| iTerm2 | 100×50 | 100×67 | height 67 |
| iTerm2 | 1×1 | 73×67 | **73×67** |
| WezTerm | 1×1 | 73×29 | **73×29** |

(iTerm2 default profile; floors likely font/profile-dependent — treat as dynamic, read
back rather than hardcode.)

### (c) Latency per write? → ~0.2–24 ms/op; a full size→pos→size set ≈ 4–40 ms.
Per-op µs across the 5-frame iTerm2 battery: size1 6274–10223; pos 7236–8708;
size2 723–23752 (second size write is cheap when it's a no-op ~0.2–1.3ms, expensive when
it re-applies). WezTerm is faster across the board: 198–3927 µs/op.
Consequence: sequentially retiling ~10 windows ≈ well under 1s; no batching machinery
needed for the MVP (#10).

### (d) WezTerm parity? → FULL parity, same code path, zero dialect differences.
One AXWindow (subrole AXStandardWindow, CG join 1/1 against 8 CG entries — phantom
layer windows again, join by id per spike-03), settable=true, exact honor, stable at
first poll, clamp behavior identical in kind. No AppleScript needed at all: window found
via AX enumerate, app launched with `open -a WezTerm`, quit via `pkill -x wezterm-gui`
(WezTerm has NO .sdef / NSAppleScriptEnabled, and no iTerm2→WezTerm Automation grant
exists — osascript quit would fire a consent prompt; audit F3).

## AXEnhancedUserInterface (research doc :58-59)
Read err=0 value=false (present, CFBoolean, settable) on BOTH apps' app elements —
VoiceOver off. The disable-before-write branch therefore never fired live; the probe
carries the read→disable→restore logic (kCFBooleanFalse/True) and a truly missing
attribute is distinguishable as -25205 kAXErrorAttributeUnsupported (audit F2). The
interference claim itself is UNVERIFIED on this Mac (would need VoiceOver on).

## Environment facts
- No macOS native-tiling defaults set (no EnableTiling* keys; Stage Manager
  GloballyEnabled=0) → interference risk for programmatic writes low on this config;
  full question stays #7's (audit F6).
- Exit-code contract: probe exits 0 iff writes .success AND readback stable; the
  match-vs-request verdict is DATA (clamp probes correctly print matchesRequest=false
  and exit 0 — audit F5).

## UNVERIFIED edges (explicit)
- Cross-display size clamping (single-display Mac) — the size→pos→size ordering is
  carried on Rectangle's authority, not local observation.
- AXEnhancedUserInterface=true interference (VoiceOver off here).
- Behavior under macOS native tiling actively enabled → #7.

## Anomaly log (honest record — RECURRENCE of spike-03's)
The spike window 78164 was externally closed (plausibly by the user after the done-note
cue; it was a conspicuous 73×67 stamp) before the scripted cleanup ran; `close window id
78164` errored -1728 "Can't get window id". Nothing was mutated by the failed close;
baseline verified restored three ways (AX count 15, CG id-join 15/15, AppleScript id set
== pre-spike baseline). Lesson promoted to TRAP-8: spike cleanup must treat
already-gone as success, and && chains must not let a failed close swallow the
verification steps behind it.

## Consequences for the build
- #9 expectation ledger: epsilon 1.0 is generous (readbacks were exact); deadline 500ms
  is generous (observed <50ms); a .success write that reads back clamped must classify
  as "applied-with-clamp", not external.
- #10: no write batching needed; verify by readback, not by AXError.
- #8 layout math: column widths/heights must respect per-app dynamic minimums (read
  back, don't hardcode 73×67).
- Packaging (#13): none of this required AppleScript — pure AX + open/pkill suffices
  app-agnostically.
