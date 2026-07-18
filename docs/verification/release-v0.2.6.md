# Release v0.2.6 verification

**Date:** 2026-07-18

## Release

- Release: https://github.com/EvanCNavarro/TermTile/releases/tag/v0.2.6
- Workflow run: https://github.com/EvanCNavarro/TermTile/actions/runs/29657850787
- Tag commit: `a9ec44a373a264420d19d86aeda158c5b5f9b131`
- Bundle version: `0.2.6`
- Build version: `138`

## Workflow Gate

The tag-triggered Release workflow passed:

- Swift test gate.
- Strict SwiftLint gate.
- Developer ID signing identity import.
- Packaged app smoke test.
- Notarization and stapling.
- Zip and checksum generation.
- Signed Sparkle appcast generation.
- Build provenance attestation.
- GitHub Release creation.

## Published Asset Checks

Downloaded the published `v0.2.6` assets from GitHub Releases:

```sh
gh release download v0.2.6 --repo EvanCNavarro/TermTile \
  --pattern 'TermTile-v0.2.6.zip' \
  --pattern 'TermTile-v0.2.6.zip.sha256' \
  --pattern 'appcast.xml'
```

Verified:

- `env LC_ALL=C LANG=C shasum -a 256 -c TermTile-v0.2.6.zip.sha256` passed.
- `gh attestation verify TermTile-v0.2.6.zip --repo EvanCNavarro/TermTile` passed.
- `appcast.xml` points to `TermTile-v0.2.6.zip`, includes `shortVersionString` `0.2.6`,
  Sparkle build version `138`, an EdDSA signature, and embedded 0.2.6 release notes.
- The downloaded app reports `CFBundleShortVersionString` `0.2.6`, `CFBundleVersion` `138`,
  `SUEnableAutomaticChecks` `false`, and the expected latest-release `SUFeedURL`.
- `codesign --verify --deep --strict --verbose=2 TermTile.app` passed.
- `xcrun stapler validate TermTile.app` passed.
- `spctl --assess --type execute -vv TermTile.app` accepted the app as notarized Developer ID
  software from `Developer ID Application: Evan Navarro (XG9SBNWNXT)`.

## Sparkle Availability

The latest appcast URL now resolves to the 0.2.6 item:

```text
title: 0.2.6
sparkle:shortVersionString: 0.2.6
sparkle:version: 138
enclosure: https://github.com/EvanCNavarro/TermTile/releases/download/v0.2.6/TermTile-v0.2.6.zip
edSignature: present
```

## User-Facing Downgrade Indicator Smoke

On 2026-07-18, installed an indicator-capable downgrade-test build at `/Applications/TermTile.app`
to let the menu-bar indicator see the public `v0.2.6` appcast as an available update.

Important distinction: the real `v0.2.5` release cannot show the new indicator because the indicator
code shipped in `v0.2.6`. This smoke used current indicator-capable code with only the installed bundle
metadata lowered below the published appcast:

- `CFBundleShortVersionString`: `0.2.5`
- `CFBundleVersion`: `137`
- Signing: local `TermTile Dev Signing`
- Installed path: `/Applications/TermTile.app`

Validation:

- `codesign --verify --deep --strict --verbose=2 /Applications/TermTile.app` passed.
- `scripts/test-packaged-app.sh /Applications/TermTile.app` passed.
- `TERMTILE_UPDATE_PROBE_SMOKE=1 /Applications/TermTile.app/Contents/MacOS/TermTile` reported:

```text
UPDATE_PROBE_SMOKE armed
UPDATE_PROBE_SMOKE available
UPDATE_PROBE_SMOKE finished
```

The app was then launched normally from `/Applications/TermTile.app` for visual inspection of the
menu-bar update indicator.

## Local Workflow Evidence

Pre-release local candidate checks, including iTerm content-drag and screenshot-region drag QOL
verification, are recorded in `docs/verification/release-v0.2.6-local.md`.
