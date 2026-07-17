# Notarization Runbook

TermTile distributes outside the Mac App Store, so public releases use Apple's Developer ID
notarization flow: sign with Developer ID, submit the signed app to Apple Notary, require an
`Accepted` result, staple the ticket to the app, validate the stapled ticket, and run Gatekeeper
assessment before creating the release zip.

## Current Evidence

- `v0.2.1` shipped with Developer ID signing from team `XG9SBNWNXT`, but its public zip was created
  before Apple returned an accepted ticket. A fresh download still has no stapled ticket and
  `spctl --assess` rejects it as `Unnotarized Developer ID`.
- Old invalid job `992020e6-0535-4119-99f0-33517bfd1939` proved the first submission lacked hardened
  runtime across TermTile and Sparkle executable code. That was fixed before `v0.2.1`.
- Fixed TermTile job `ca11052c-2117-4c9f-a3b9-d5453d59a9ed` returned `Accepted`.
- Retry TermTile job `868dd795-f6ef-4024-82c1-60b04d487a72` returned `Accepted`.
- The accepted TermTile job was not the already-published v0.2.1 zip's code hash, so it cannot be
  used to staple that published asset. Notarize the exact release artifact before zipping.
- Differential job `a4b780fa-92be-4f61-bfc8-5aedd613ada8` submitted a tiny signed `NotaryProbe`
  app using the same Developer ID team and hardened runtime. It also returned `Accepted`, confirming
  the earlier stall was not a TermTile bundle-specific signing defect.

## Release Gate

`.github/workflows/release.yml` runs `scripts/notarize-app.sh` after the Developer ID packaged-app
smoke test and before `Package + checksum`. That ordering is load-bearing: the zip, checksum,
Sparkle appcast, provenance attestation, and GitHub release must all refer to the stapled app.

The release Notary step requires these GitHub secrets:

- `TERMTILE_NOTARY_KEY_P8_BASE64`
- `TERMTILE_NOTARY_KEY_ID`
- `TERMTILE_NOTARY_ISSUER_ID`

The script then performs the release-critical checks:

```sh
scripts/notarize-app.sh path/to/TermTile.app
xcrun stapler validate path/to/TermTile.app
spctl --assess --type execute --verbose=4 path/to/TermTile.app
```

If Apple Notary returns anything other than `Accepted`, if stapling fails, or if Gatekeeper rejects
the app, the release workflow must fail before publishing any zip.

## Read-Only Status Checks

Use `scripts/notary-status.sh` to inspect existing jobs without uploading anything:

```sh
TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8 \
TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID \
TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID \
scripts/notary-status.sh
```

Poll specific submissions:

```sh
TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8 \
TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID \
TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID \
scripts/notary-status.sh \
  ca11052c-2117-4c9f-a3b9-d5453d59a9ed \
  868dd795-f6ef-4024-82c1-60b04d487a72 \
  a4b780fa-92be-4f61-bfc8-5aedd613ada8
```

Fetch logs only when a job is terminal or Apple Support asks for them:

```sh
TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8 \
TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID \
TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID \
TERMTILE_NOTARY_FETCH_LOGS=1 \
scripts/notary-status.sh a4b780fa-92be-4f61-bfc8-5aedd613ada8
```

Do not create duplicate Notary submissions unless there is a new artifact or a new hypothesis to
test. Re-poll existing jobs with `scripts/notary-status.sh`; submit release artifacts through
`scripts/notarize-app.sh`.

## Post-Release Verification

After a tag workflow publishes a release, verify the downloaded artifact, not a local build:

```sh
gh release download vX.Y.Z --repo EvanCNavarro/TermTile --pattern 'TermTile-vX.Y.Z.zip*'
ditto -x -k TermTile-vX.Y.Z.zip unpacked
codesign --verify --deep --strict --verbose=2 unpacked/TermTile.app
xcrun stapler validate unpacked/TermTile.app
spctl --assess --type execute --verbose=4 unpacked/TermTile.app
env LC_ALL=C LANG=C shasum -a 256 -c TermTile-vX.Y.Z.zip.sha256
gh attestation verify TermTile-vX.Y.Z.zip --repo EvanCNavarro/TermTile
```
