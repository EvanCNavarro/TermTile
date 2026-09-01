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

## Degradation diagnostics (`#37f`)

`screenshots/session-tint-diagnostics-2026-08-31.png`, rendered via
`TERMTILE_GALLERY_TINT_DIAGNOSTICS=1`, which seeds one row of every shape a user can actually meet.
The gallery injects no tinting controller — it has no business writing escape sequences into live
terminals — so without the seed the panel would render empty and prove nothing.

| row | renders |
|---|---|
| painted, idle | `termtile — Idle`, no reason line |
| painted, blocked | `invela-marketing-suite — Waiting on you`, no reason line |
| first sighting | `portfolio — Not yet` + "Just noticed — TermTile decides on the next check." |
| unrecognised state | `pushtext — Not yet` + "Running, but TermTile doesn't recognise what it's doing." |
| unjoinable | `shared-folder — Not yet` + "Several terminals share this folder, so TermTile can't tell which window this is." |

The third and fourth rows are the point of the feature: both are `.unknown`, and the user's correct
reaction differs — wait, versus a marker is missing (EvanCNavarro/TermTile#6). `TintDecision.hadBaseline`
is what separates them; without it both would read the same and the panel would be decoration.

## The whole stack against real sessions

Real reader, real probe, real join, real classifier, real `OSCColorWriter`
(`TintingEndToEndLiveTests`, six live sessions):

```
E2E  termtile               -> /dev/ttys005  working  wrote=true
E2E  invela-marketing-suite -> /dev/ttys003  blocked  wrote=true   <-- WRONG, see below
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


## RETRACTION (same day)

The `blocked` classifications above are **false positives**, and so is the superiority claim made
from them.

`⧉ waiting-on-a-person` is Claude Code's per-session task LABEL, not a state. Measured across five
live sessions: three carried that slot with three different values (`waiting-on-a-person`,
`icon-marks`, `portfolio-roster`), all three were IDLE by the session-name glyph, and two sessions
had no slot at all.

This document previously said TermTile was better than the out-of-tree poller because it reported
`blocked` on `ttys003` where the poller's glyph said idle. **The poller was right.** That session
was idle; TermTile was reading a task name. The claim is withdrawn.

Blocked-detection is now absent (ADR 0006 finding 10). Everything else in this document stands:
the join, the ready/working classification, the write path, and the rendered UI were all measured
independently of the retracted marker.


## Blocked detection, restored and earned (same day)

The retraction above left blocked-detection absent. A blocked session was then CREATED rather than
waited for: a scratch Claude session driven into an `AskUserQuestion`, which blocks on a human
regardless of permission mode, read through the same ranged AX read the production adapter uses.

Marker adopted: **`Esc to cancel`**. A/B at the 400-char window the blocked matcher actually uses —
present on the blocked session, absent on all six others. At 2000 chars one non-blocked session DID
match, because the probe's own output was in its scrollback; the narrower window excluded it. That
is mitigation, not immunity — a session displaying the string still matches.

Full live pass, **7 of 7 correct** against the session-name glyph as ground truth:

```
LIVE-PASS2  tmp                    -> /dev/ttys007  blocked   (glyph ✳ "idle")
LIVE-PASS2  invela-marketing-suite -> /dev/ttys003  ready     (glyph ✳)
LIVE-PASS2  termtile               -> /dev/ttys005  working   (glyph ◑)
LIVE-PASS2  evancnavarro           -> /dev/ttys001  working   (glyph ⠸)
LIVE-PASS2  ChangeFabric           -> /dev/ttys000  ready     (glyph ✳)
LIVE-PASS2  pushtext               -> /dev/ttys002  ready     (glyph ✳)
LIVE-PASS2  portfolio              -> /dev/ttys004  ready     (glyph ✳)
```

`ttys007` is the case the retraction was about: the glyph says idle, TermTile says blocked. This
time TermTile is right, **verifiably** — the block was created on purpose. That is the `✳` ambiguity
the out-of-tree hook exists to resolve, now actually resolved rather than apparently resolved.


## WezTerm: the OSC write path does NOT work (EvanCNavarro/TermTile#13)

`screenshots/wezterm-osc-ignored-2026-08-31.png`.

Writing `\033]1337;SetColors=bg=6A1B9A\a` to a live WezTerm session's tty left the background
BLACK. The instrument was checked before concluding, because "nothing happened" and "the write
never arrived" are indistinguishable: plain text written to the SAME tty
(`WEZTERM-CHANNEL-CHECK-12345`) rendered in the window, and is visible in the screenshot. The
channel works; WezTerm consumes the sequence and does nothing.

**This reverses an argument made repeatedly during this work** — that OSC is a terminal protocol
rather than an app API, so Tier 1 was the more portable route and Tier 2's iTerm2-only nature
counted against it. Tier 1 is also iTerm2-only. Portability does not separate the tiers.

Only the WRITE path was measured. WezTerm's read path (AX text areas, a badge, a session-id
environment variable) was not tested and is moot while the write fails — an untested gap, not a
verified absence.

README and ADR 0006 now scope Session tint to iTerm2.


## Packaged-app verification, and why it matters for the domain trap

The feature had only ever run from `.build/debug`. Built and smoke-tested as a real bundle:

- `dist/TermTile.app` carries the tinting symbols — the feature survives packaging.
- Bundle id is `dev.ecn.apps.termtile`, so `UserDefaults.standard` resolves to the **correct**
  domain. **The debug-binary trap recorded above does NOT apply to the shipped app** — it is
  specific to running the bare executable, which has no `Info.plist` and therefore falls back to
  the process-name domain.
- `scripts/test-packaged-app.sh` (sandbox `HOME`, never touches `/Applications`): launched,
  rendered the gallery, armed the update probe, stayed alive 8/8, 0 crash reports.

**Signing:** both the newly built app and the one currently installed are signed
`TermTile Dev Signing` with `TeamIdentifier=not set` — like for like, so installing is not a
signing downgrade. A Developer ID identity exists on this machine if the stable-TCC posture is
wanted later.

**NOT verified:** whether a freshly installed build keeps its Accessibility grant, or needs
re-approval in System Settings. That cannot be determined without installing, and the app already
ships an **Allow Accessibility** action and a **Reset & Open Settings** recovery for exactly this
case. Everything measured above was measured with the DEBUG binary inheriting the terminal's grant;
the packaged app's own TCC identity is untested.

## What actually gates daily use

The installed app is from 2026-07-20 and contains **zero** tinting symbols. The feature cannot be
used daily until a build carrying it is installed — which is the real blocker behind both
EvanCNavarro/TermTile#27 (retire the poller) and EvanCNavarro/TermTile#12 (Tier 2), not the passage
of time.
