# Session tinting — live verification (2026-08-31)

Covers backlog tasks `#37a`–`#37e2` (ADR 0006 Tier 1). Written because the suite passing proves
nothing here: `.engine/MEMORY.md` defines this project's live surface as AX against ANOTHER app's
real windows, and this feature also WRITES to real terminal devices.

## Rendered UI (FL-9)

Real `MenuBarContent` in the gallery window (`TERMTILE_SELFTEST=1 TERMTILE_GALLERY=1`), captured
with `screencapture -l<window-id>`:

| state | evidence |
|---|---|
| tinting off | `screenshots/session-tint-off-2026-08-31.png` — the `SESSION TINT` card shows the toggle only; no picker, no caption |
| tinting on | `screenshots/session-tint-on-2026-08-31.png` — toggle checked, `Ready shade` picker showing the PERSISTED value (`Louder`), privacy caption wrapping across three lines without overflow |

The on-state screenshot doubles as proof that `readyIntensity` round-trips from `UserDefaults` into
the rendered control: the suite was seeded with `louder` and the picker rendered `Louder`.

## The whole stack against real sessions

Real reader, real probe, real join, real classifier, real `OSCColorWriter`
(`TintingEndToEndLiveTests`, six live sessions):

```
E2E  termtile               -> /dev/ttys005  working  wrote=true
E2E  invela-marketing-suite -> /dev/ttys003  blocked  wrote=true
E2E  ChangeFabric           -> /dev/ttys000  ready    wrote=true
E2E  evancnavarro           -> /dev/ttys001  working  wrote=true
E2E  pushtext               -> /dev/ttys002  ready    wrote=true
E2E  portfolio              -> /dev/ttys004  ready    wrote=true
```

## The composition root, and the trap that hid it

Running the built app is the only thing that exercises `makeTintingDriver` +
`startTintingIfEnabled`. Proving it needs a DISCRIMINATOR, because the out-of-tree poller this
feature replaces writes to the same sessions:

- the poller sets colours over **AppleScript**, which lands EXACT values (`#143C22` reads back as
  `5139,15419,8737`)
- TermTile writes **OSC 1337**, which iTerm converts (`#1D7538` reads back as `0,26380,9230`)

So an OSC-converted value on screen could only have come from TermTile. With the app running and
the shade set to `loudest`, no session showed the poller's exact value — the app had painted them.

**THE TRAP, recorded because it produced a confident wrong conclusion first:** the bare
`.build/debug/TermTile` executable has NO `Info.plist`, so `UserDefaults.standard` resolves to the
**`TermTile`** domain (the process name), NOT `dev.ecn.apps.termtile`. Seeding the real bundle-id
domain and launching the debug binary therefore proves nothing: the app reads absent keys, defaults
`tintingEnabled` to false, and correctly does nothing. That reads identically to broken wiring.

The instrument would have reported "no writes" whether the feature worked or not. Seed the
`TermTile` domain when testing the debug binary, or test the packaged `.app`.

## Not covered

- Visual flicker over a long soak. The 200-write load test showed no BUFFER corruption, but AX
  reads a rendered view and cannot see a transient repaint artifact.
- Long-run behaviour alongside the out-of-tree poller. Both write every ~5s; they will fight until
  the poller is retired (`#37g`). That is expected, not a defect, and is why `#37g` exists.
