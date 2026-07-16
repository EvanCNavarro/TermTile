# Releasing TermTile

Versioning mirrors RememBar's discipline (RememBar-audit §7), with one deliberate improvement.

## Versions

- **Marketing version** (`CFBundleShortVersionString`, what users see) = the git tag minus its
  leading `v`. `release.yml` passes `SHORT_VERSION="${GITHUB_REF_NAME#v}"` to `build-app.sh`, so
  tag `v0.2.0` ships as `0.2.0`. Tags follow SemVer: `vMAJOR.MINOR.PATCH`.
- **Build version** (`CFBundleVersion`, what Sparkle compares to decide "is this newer?") =
  `git rev-list --count HEAD` — a monotonic commit count. This is the improvement over RememBar's
  dots-stripped scheme (audit §8.5): `1.0.0` and `0.10.0` both dots-strip to `100` and collide;
  a commit count never does. It only has to increase, and it always does.

## Release notes are single-source

One file per version — `release-notes/<version>.md` — authored **before** tagging. `release.yml`
uses it twice, so there is exactly one place to write them:

1. **Sparkle "What's new" dialog** — staged as `dist/TermTile-<tag>.md` (matching the archive
   basename) and inlined into the appcast `<description>` via `generate_appcast --embed-release-notes`.
2. **GitHub release body** — `gh release create --notes-file release-notes/<version>.md`.

If the file is missing the release still ships (a CI warning + auto-generated notes fallback), but
the "What's new" section will be empty — so write it first.

## Cutting a release

```
# 1. Write the notes (before tagging):
$EDITOR release-notes/0.2.0.md

# 2. Commit + tag + push — the tag fires release.yml:
git add release-notes/0.2.0.md && git commit -m "docs: 0.2.0 release notes"
git tag -a v0.2.0 -m "TermTile v0.2.0"
git push origin master v0.2.0
```

`release.yml` (on the `v*` tag) then: vendors Sparkle → runs the test/lint gate → builds + signs
the `.app` → smoke-tests it → zips + checksums → generates the EdDSA-signed appcast with embedded notes → attests
provenance → (optional) VirusTotal → publishes the GitHub Release with the zip, `.sha256`, and
`appcast.xml`. Existing users get the update offered automatically via the `SUFeedURL`.

## Signing

Public releases must not be ad-hoc signed. macOS Accessibility/Input Monitoring grants bind to the
app's designated code requirement; an ad-hoc build makes that requirement the per-build cdhash, so an
update can leave System Settings showing TermTile enabled while the new binary is denied.

`release.yml` imports a signing identity from GitHub secrets and sets `TERMTILE_SIGN_IDENTITY` before
calling `scripts/build-app.sh`. Set the repo variable `TERMTILE_SIGN_IDENTITY` to the exact Keychain
identity name, for example `Developer ID Application: Evan Navarro (TEAMID)`. If that variable is
absent, CI falls back to the stable self-signed `TermTile Dev Signing` identity. The fallback does
**not** provide Gatekeeper trust or notarization, but it gives TCC a stable code identity across
releases from that signing line.

Required release secrets:

- `TERMTILE_RELEASE_SIGNING_CERT_P12_BASE64`
- `TERMTILE_RELEASE_SIGNING_CERT_PASSWORD`
- `SPARKLE_ED_PRIVATE_KEY`
- `VIRUSTOTAL_API_KEY` (optional)

Developer ID notarization is prepared but not release-gated yet. `scripts/notarize-app.sh` submits a
parent-preserving zip to Apple with `notarytool`, requires an `Accepted` result, staples the ticket,
validates the stapled app, and runs `spctl --assess`. Wire it into `release.yml` only after a real
submission completes reliably; a stuck Notary job should block the notarized cut, not silently ship a
fake notarized release.
