# Update Indicator Visibility Native Proof

**Date:** 2026-07-18

**Candidate installed for downgrade proof:** `/Applications/TermTile.app`

- `CFBundleShortVersionString`: `0.2.5`
- `CFBundleVersion`: `137`
- Built from current local code with:
  `SHORT_VERSION=0.2.5 TERMTILE_BUILD_NUMBER=137 scripts/install-app.sh`
- Public appcast observed at `v0.2.6`, `sparkle:version` `138`, so Sparkle should report an
  available update for this candidate.

## Automated Proof

- `scripts/test-packaged-app.sh /Applications/TermTile.app`
  - Passed.
  - The packaged app launched, rendered the native gallery, armed the passive update probe, finished
    the probe, stayed alive, and produced no new crash report.
- `TERMTILE_UPDATE_PROBE_SMOKE=1 /Applications/TermTile.app/Contents/MacOS/TermTile`
  - Reported:

```text
UPDATE_PROBE_SMOKE armed
UPDATE_PROBE_SMOKE available
UPDATE_PROBE_SMOKE finished
```

## Native Visual Proof

- Menu-bar glyph, update available:
  `menubar-glyph-composited-visible-update-2026-07-18.png`
- Menu-bar glyph tight crop:
  `menubar-glyph-composited-visible-update-tight-2026-07-18.png`
  - Orange-family component: `148` pixels, bounding box `x=2206..2219`, `y=41..54` in the top-strip
    screenshot.
- Overflow button tight crop:
  `gallery-overflow-button-composited-visible-update-tight-2026-07-18.png`
  - Orange-family component: `140` pixels, bounding box `x=58..71`, `y=42..55`.
- Enabled dropdown row tight crop:
  `gallery-overflow-dropdown-composited-enabled-update-tight-2026-07-18.png`
  - Row dot orange-family component: `140` pixels, bounding box `x=258..271`, `y=77..90`.
  - Closed trigger dot also remains visible in the same crop.

## Pitstop Result

The initial SwiftUI overlay rendered in offscreen tests but did not survive the live `MenuBarExtra`
host. The final implementation uses a TermTile-owned original-color composited menu-bar image while
still sourcing the attention size/color from MacFaceKit tokens.

The first dropdown capture exposed a real UX gap: after Sparkle found an available update, the
"Check for Updates" row could still render disabled. `Updater.canOpenUpdateCheck` now keeps that row
actionable once an available update is known.
