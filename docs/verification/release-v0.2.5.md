# Release v0.2.5 verification

**Date:** 2026-07-18

## Release

- Release: https://github.com/EvanCNavarro/TermTile/releases/tag/v0.2.5
- Workflow run: https://github.com/EvanCNavarro/TermTile/actions/runs/29652937004
- Tag commit: `5656c89ecd5443add131d7d7023fefd45f0672b9`
- Bundle version: `0.2.5`
- Build version: `134`

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

Downloaded the published `v0.2.5` assets from GitHub Releases:

```sh
gh release download v0.2.5 --repo EvanCNavarro/TermTile \
  --pattern 'TermTile-v0.2.5.zip' \
  --pattern 'TermTile-v0.2.5.zip.sha256' \
  --pattern 'appcast.xml'
```

Verified:

- `env LC_ALL=C LANG=C shasum -a 256 -c TermTile-v0.2.5.zip.sha256` passed.
- `gh attestation verify TermTile-v0.2.5.zip --repo EvanCNavarro/TermTile` passed.
- `appcast.xml` points to `TermTile-v0.2.5.zip`, includes `shortVersionString` `0.2.5`,
  Sparkle build version `134`, an EdDSA signature, and embedded 0.2.5 release notes.
- The downloaded app reports `CFBundleShortVersionString` `0.2.5` and `CFBundleVersion` `134`.
- `codesign --verify --deep --strict --verbose=2 TermTile.app` passed.
- `xcrun stapler validate TermTile.app` passed.
- `spctl --assess --type execute -vv TermTile.app` accepted the app as notarized Developer ID
  software from `Developer ID Application: Evan Navarro (XG9SBNWNXT)`.

## Sparkle Availability

The latest appcast URL now resolves to the 0.2.5 item:

```text
title: 0.2.5
sparkle:shortVersionString: 0.2.5
sparkle:version: 134
enclosure: https://github.com/EvanCNavarro/TermTile/releases/download/v0.2.5/TermTile-v0.2.5.zip
```
