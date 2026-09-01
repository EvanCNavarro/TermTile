# Session tint colour space — EvanCNavarro/TermTile#29

**Date:** 2026-09-01 · **Symptom reported:** "why are the greens changing colors etc"

## What was happening

Two writers were painting the same window every ~5s and disagreeing about what a hex means.
The out-of-tree poller sets `background color` over AppleScript; TermTile writes OSC 1337
`SetColors`. Given the identical six hex digits they produced different colours, so the window
alternated between them.

## Cause

An OSC 1337 `SetColors` triple is interpreted as **Display P3**. The AppleScript `background
color` property both sets and reports **Generic RGB**.

### How the spaces were identified

Five colours written over OSC to a scratch window with no agent — the poller does not tint
those, and an earlier run WAS contaminated by it overwriting mid-measurement. Every pairing of
macOS's RGB spaces was then applied to the requests and scored against the readings.

| requested | terminal rendered | `displayP3 → genericRGB` predicts | error |
|---|---|---|---|
| `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | 0 |
| `#FF0000` | `#FF0000` | `#FF0000` | 0 |
| `#808080` | `#6D6D6D` | `#6D6D6D` | 0 |
| `#143C22` | `#003018` | `#003018` | 0 |
| `#111417` | `#0E1012` | `#0E1012` | 0 |

No free parameters — that is AppKit's own conversion applied blind. Nearest rival pairing
(`adobeRGB → genericRGB`) was out by 9.

### Confirmed on held-out colours

An exact fit on the data that produced it is not evidence. Two colours were chosen to split the
Display P3 model from the sRGB one by 92 and 98 points, and both predictions were written down
before the run.

| write | P3 model | sRGB model | terminal said | picks |
|---|---|---|---|---|
| `#6CF6FC` | `#03FBFE` | `#5FF6FB` | `#03FBFE` | P3 |
| `#6EFF00` | `#00FF00` | `#62FF07` | `#00FF00` | P3 |

AppKit agrees with the terminal at full precision: 13.434/255 predicted, 13.432/255 measured.

## Fix

`TermTileKit/DisplayP3Compensation` converts Generic RGB → Display P3 before `OSCSequence`
formats the escape. It lives in the writer, not the palette: it is a property of the OSC wire
format, and an Apple Events adapter (#12) would need the opposite of it.

## Live proof

`PaletteRendersAsRequestedLiveTests` drives the real `OSCColorWriter` at a real session and
reads the colour back out of iTerm2.

```
LIVE-RENDER ready    requested #143C22  got (20,60,34)   drift 0
LIVE-RENDER blocked  requested #4A320F  got (74,50,15)   drift 0
LIVE-RENDER normal   requested #111417  got (17,20,23)   drift 0
LIVE-RENDER subtle   requested #0E2B18  got (13,43,24)   drift 1
LIVE-RENDER louder   requested #185634  got (24,86,52)   drift 0
LIVE-RENDER loudest  requested #1D7538  got (29,117,56)  drift 0
```

`subtle` is 1/255 low because `#0E2B18` has no exact 8-bit Display P3 preimage. That is a
property of the colour, not an error in the transform.

### The writers now agree

Alternating both paths on one window, three rounds:

```
AppleScript(poller) -> 5139,15419,8737
OSC(TermTile)       -> 5072,15344,8762
```

Identical at 8 bits. Residual 75/65535 = 0.29 of one 8-bit step, against a zeroed red channel
before the fix.

## Two of my own explanations that were wrong

- **"`#FF0000` surviving exact rules out a gamut conversion."** It does not. A pure primary
  clamps back to itself under exactly the conversion it appeared to rule out.
- **"The profile says `Color Space = sRGB`, so the source cannot be P3."** Those 78 keys
  describe how each stored profile colour is encoded, not how an escape sequence is read. The
  config read predicted the opposite of the measurement.

Two measurement errors were also found and corrected mid-investigation: the readback string
`0122536093` parses ambiguously as `(0,12253,6093)` or `(0,1225,36093)` and had been eyeballed
that way, and the first live readback truncated 16→8 bits instead of rounding, biasing every
channel low by one and reporting drift 1 on all six colours.

## Not verified

Whether iTerm's interpretation follows the attached display's profile. This machine has a
single display, so only a fixed transform could be tested. Tracked as EvanCNavarro/TermTile#31.
