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

## First fix — worked, and was the wrong shape

`TermTileKit/DisplayP3Compensation` converted Generic RGB → Display P3 before `OSCSequence`
formatted the escape. Live-proven, merged as #32, and superseded within the hour. It corrected
for a default rather than overriding it, and it carried three dependencies it did not need:
iTerm's undocumented default space, AppKit agreeing with iTerm about Generic RGB's primaries, and
the transform being display-independent.

## Actual fix — name the space

**I characterised the protocol's behaviour without reading its specification.** `SetColors`
accepts `cs:RRGGBB` where `cs` is `srgb`, `rgb` (the device space) or `p3` — documented since
iTerm 3.3. Reading that first would have skipped the entire space-identification exercise above.

That exercise was not wasted, because it makes the default legible, and the prefix let me confirm
the default DIRECTLY instead of inferring it:

| write | readback | says |
|---|---|---|
| `143C22` (bare) | `0,12253,6093` | — |
| `p3:143C22` | `0,12253,6093` | **byte-identical: the bare default IS Display P3** |
| `srgb:143C22` | `4488,11980,6594` | prefix honoured, as predicted |
| `rgb:143C22` | `5139,15419,8737` | **I predicted `#112F1A`. Wrong.** |

That last value is exactly what the AppleScript poller writes. iTerm's device space and
AppleScript's `background color` space are the same one, so the palette hex needs **no conversion
at all**.

`OSCSequence.setBackground` now emits `bg=rgb:HEX`. All colour arithmetic is deleted, and the
write path returns to the pure core with no AppKit in it.

Unconverted, under `rgb:`, every colour round-trips exactly — including the discriminator colour
the P3 default mangled to `#03FBFE`:

```
rgb:143C22 -> #143C22    rgb:0E2B18 -> #0E2B18    rgb:FFFFFF -> #FFFFFF
rgb:4A320F -> #4A320F    rgb:185634 -> #185634    rgb:6CF6FC -> #6CF6FC
rgb:111417 -> #111417    rgb:1D7538 -> #1D7538
```

## Live proof

`PaletteRendersAsRequestedLiveTests` drives the real `OSCColorWriter` at a real session and
reads the colour back out of iTerm2.

```
LIVE-RENDER ready    requested #143C22  got (20,60,34)   drift 0
LIVE-RENDER blocked  requested #4A320F  got (74,50,15)   drift 0
LIVE-RENDER normal   requested #111417  got (17,20,23)   drift 0
LIVE-RENDER subtle   requested #0E2B18  got (14,43,24)   drift 0
LIVE-RENDER louder   requested #185634  got (24,86,52)   drift 0
LIVE-RENDER loudest  requested #1D7538  got (29,117,56)  drift 0
```

Every colour exact. Under the first fix `subtle` was 1/255 low — that residual was an artefact of
the conversion, not of the colour, and it vanished with the arithmetic. The test now asserts
`drift == 0` rather than `<= 1`, so the instrument can say NO more sharply than before.

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

Whether an iTerm older than 3.3 parses the `cs:` prefix. This machine runs 3.6.11. The docs carry
the prefix as far back as the 3.3 documentation, so the exposure is versions predating that.

The display-dependence question (#31) is **resolved, not deferred**: there is no transform left to
be display-dependent, and `rgb:` names the same device space AppleScript does, so the two write
paths cannot diverge on any display.

## Lesson

Read the protocol's specification before characterising its behaviour. The measurement work was
careful, held-out-validated and correct — and entirely unnecessary. A single documentation fetch,
done first, would have replaced it.
