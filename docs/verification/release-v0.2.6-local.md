# Release v0.2.6 Local Candidate Verification

**Date:** 2026-07-18
**Candidate:** `dist/TermTile.app`
**Version:** `CFBundleShortVersionString = 0.2.6`
**Signing:** `Developer ID Application: Evan Navarro (XG9SBNWNXT)`
**Release status:** local candidate only; not notarized, zipped, published, or appcast-listed here.

## Automated Gate

- `scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict`
  - Passed with 255 tests.
  - SwiftLint found 0 violations.
- `SHORT_VERSION=0.2.6 scripts/build-app.sh && scripts/test-packaged-app.sh dist/TermTile.app`
  - Passed with the local development signing identity.
  - Packaged smoke launched the app, rendered gallery, armed and finished the passive update probe,
    stayed alive, and produced no new crash report.
- `SHORT_VERSION=0.2.6 TERMTILE_SIGN_IDENTITY="Developer ID Application: Evan Navarro (XG9SBNWNXT)"
  TERMTILE_DISABLE_LIBRARY_VALIDATION=0 scripts/build-app.sh`
  - Rebuilt the same candidate with Developer ID signing for live local workflow checks.
- `REQUIRE_STABLE_CODESIGN=1 REQUIRE_DEVELOPER_ID_CODESIGN=1 REQUIRE_CODESIGN_TEAM_ID=XG9SBNWNXT
  scripts/test-packaged-app.sh dist/TermTile.app`
  - Passed against the Developer-ID-signed local candidate.
  - Confirmed the package was not ad-hoc signed and did not carry the local library-validation
    entitlement.

## Live Drag QOL Checks

Preconditions observed from the real machine:

- `/Applications/TermTile.app` was public `0.2.5` and was temporarily stopped before each candidate
  check.
- The `0.2.6` candidate was launched directly from `dist/TermTile.app`.
- User defaults had `reorderOnDrag = 1`, `targetBundleID = "com.googlecode.iterm2"`, and
  `reorderStrategy = adaptive`.
- iTerm2 was running with a large focused window named `ChangeFabric`.
- After each check, the candidate process was stopped and `/Applications/TermTile.app` was relaunched.

### iTerm Content Drag

Command path: launch `dist/TermTile.app`, activate iTerm2, use `cliclick` to drag inside the
`ChangeFabric` terminal content area.

Evidence:

```text
candidate_pid=25646
target_window=ChangeFabric
drag_from=432,295 drag_to=864,295
before=0,38,1728,1030
after=0,38,1728,1030
PASS: iTerm content-drag did not change window bounds
```

### Screenshot Region Drag

Command path: launch `dist/TermTile.app`, activate iTerm2, start `screencapture -ic`, then use
`cliclick` to drag a screenshot region starting inside the `ChangeFabric` terminal window.

Evidence:

```text
candidate_pid=31087
target_window=ChangeFabric
screenshot_region=576,381->796,521
before=0,38,1728,1030
after=0,38,1728,1030
PASS: screenshot-region drag did not change iTerm window bounds
```

Pitstop note: the screenshot-region shell wrapper printed the PASS evidence, then exited nonzero
because its cleanup function used zsh's read-only `status` variable. That was a verification-harness
mistake after the proof point, not an app failure. The candidate PID was then stopped explicitly and
`/Applications/TermTile.app` was relaunched; `ps` confirmed the restored process was
`/Applications/TermTile.app/Contents/MacOS/TermTile`.

## Remaining External Release Work

This file does not prove public availability. Users receive this only after the v0.2.6 release
pipeline publishes the signed/notarized zip, checksum/provenance, release notes, and Sparkle appcast.
