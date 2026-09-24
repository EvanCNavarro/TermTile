# Release v0.5.2 verification

**Date:** 2026-09-24

## Release

- Release: https://github.com/EvanCNavarro/TermTile/releases/tag/v0.5.2
- Workflow run: https://github.com/EvanCNavarro/TermTile/actions/runs/35958086530 (success)
- Tag commit: `a7d5d68`
- Bundle version: `0.5.2`
- Build version: `189` — matches `git rev-list --count HEAD`

## Published asset checks

Downloaded the published assets fresh from GitHub Releases, not reused from the local build.

```
$ env LC_ALL=C LANG=C shasum -a 256 -c TermTile-v0.5.2.zip.sha256
TermTile-v0.5.2.zip: OK

$ gh attestation verify TermTile-v0.5.2.zip --repo EvanCNavarro/TermTile
exit 0

$ codesign --verify --deep --strict --verbose=2 unpacked/TermTile.app
unpacked/TermTile.app: valid on disk
unpacked/TermTile.app: satisfies its Designated Requirement

$ xcrun stapler validate unpacked/TermTile.app
The validate action worked!

$ spctl --assess --type execute --verbose=4 unpacked/TermTile.app
unpacked/TermTile.app: accepted
source=Notarized Developer ID
```

### The detectors were battle-tested, not trusted

`gh attestation verify` printed nothing on the genuine artifact and exited 0, which is indistinguishable
from a no-op check by reading the output alone. Both detectors were therefore run against a deliberately
tampered copy — the same zip with ONE byte appended:

```
$ gh attestation verify tampered.zip --repo EvanCNavarro/TermTile
exit 1
Error: HTTP 404: Not Found (…/attestations/sha256:0d986cc…)

$ env LC_ALL=C LANG=C shasum -a 256 -c bad.sha256
tampered.zip: FAILED
shasum: WARNING: 1 computed checksum did NOT match
exit 1
```

Genuine → 0, tampered → 1, on both. The green means something.

## Sparkle appcast

```
items=1
  short=0.5.2 build=189
    url=https://github.com/EvanCNavarro/TermTile/releases/download/v0.5.2/TermTile-v0.5.2.zip
    edSignature=present (88 chars)
    embedded notes: 1761 chars, mentions 0.5.2: True
```

Build number, enclosure URL, EdDSA signature and embedded release notes all present and consistent
with the published zip.

## Behaviour of the PUBLISHED binary

The two fixes this release carries were proven during development against a locally signed build.
They were re-proven here against the CI-built artifact actually served to users, installed over the
local one at `/Applications/TermTile.app`.

**The Accessibility grant survived the bundle swap** — the property the Developer ID scheme exists
for. Evidence: the panel read `8 sessions tinted.`, which requires the AX reader to be working.

Panel height following its content (#44), driving the Session-tint toggle to change the content
height without changing anything else:

```
tint ON   window=280x789  content span=762  bands 14 / 14
tint OFF  window=280x710  content span=682  bands 14 / 14
tint ON   window=280x789  content span=762  bands 14 / 14
```

Before the fix the same sequence held the window at 823 in both states and the bands grew to 70/70.

Tint summary refreshing on open (#57): `8 sessions tinted.` on the second open of a fresh process,
where the count had previously frozen at whatever was true when the toggle last flipped.

## Method note

Panel geometry is measured over LEAF AX elements only. A union that includes the root `AXGroup`
reports a zero gap in every state, because that group always fills the window — a number that cannot
say otherwise, and one that briefly hid this defect during the investigation.
