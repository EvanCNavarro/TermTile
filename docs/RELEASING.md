# Releasing TermTile

Versioning mirrors RememBar's discipline (RememBar-audit §7), with one deliberate improvement.

## Versions

- **Marketing version** (`CFBundleShortVersionString`, what users see) = the git tag minus its
  leading `v`. `release.yml` passes `SHORT_VERSION="${GITHUB_REF_NAME#v}"` to `build-app.sh`, so
  tag `v0.2.1` ships as `0.2.1`. Tags follow SemVer: `vMAJOR.MINOR.PATCH`.
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
$EDITOR release-notes/0.2.2.md

# 2. Commit the complete release-gating diff + notes, then tag + push — the tag fires release.yml:
git status --short
git add .github/workflows/release.yml Tests README.md SECURITY.md docs HANDOFF.md release-notes/0.2.2.md
git diff --cached --stat
git commit -m "release: gate v0.2.2 on notarization"
git tag -a v0.2.2 -m "TermTile v0.2.2"
git push origin master v0.2.2
```

`release.yml` (on the `v*` tag) then: vendors Sparkle → runs the test/lint gate → builds + signs
the `.app` → smoke-tests it → notarizes and staples it → zips + checksums the stapled app →
generates the EdDSA-signed appcast with embedded notes → attests provenance → (optional) VirusTotal
→ publishes the GitHub Release with the zip, `.sha256`, and `appcast.xml`. Existing users get the
update offered automatically via the `SUFeedURL`.

## Signing

Public releases must not be ad-hoc signed. macOS Accessibility/Input Monitoring grants bind to the
app's designated code requirement; an ad-hoc build makes that requirement the per-build cdhash, so an
update can leave System Settings showing TermTile enabled while the new binary is denied.

`release.yml` imports a signing identity from GitHub secrets and sets `TERMTILE_SIGN_IDENTITY` before
calling `scripts/build-app.sh`. Set the repo variable `TERMTILE_SIGN_IDENTITY` to the exact Keychain
identity name, for example `Developer ID Application: Evan Navarro (TEAMID)`. Public release CI
does not fall back to the stable self-signed `TermTile Dev Signing` identity: the workflow fails if
`TERMTILE_SIGN_IDENTITY` is missing or is not a `Developer ID Application` identity.

`scripts/build-app.sh` still has a local-development fallback to `TermTile Dev Signing`, then ad-hoc
signing, so fresh clones can build and local developer machines can keep stable TCC grants. That
fallback is not the public release policy.

Local self-signed/ad-hoc builds may carry `com.apple.security.cs.disable-library-validation` so the
locally re-signed app can load embedded Sparkle. Developer ID release artifacts must not carry that
entitlement; release smoke rejects it before notarization and packaging.

Required release secrets:

- `TERMTILE_RELEASE_SIGNING_CERT_P12_BASE64`
- `TERMTILE_RELEASE_SIGNING_CERT_PASSWORD`
- `SPARKLE_ED_PRIVATE_KEY`
- `VIRUSTOTAL_API_KEY` (optional)

Required Notary credentials:

- `TERMTILE_NOTARY_KEY_P8_BASE64`
- `TERMTILE_NOTARY_KEY_ID`
- `TERMTILE_NOTARY_ISSUER_ID`

Developer ID notarization is release-gated. `release.yml` runs `scripts/notarize-app.sh` after the
Developer ID smoke test and before `Package + checksum`, so the public zip contains the stapled app.
The script submits a parent-preserving zip to Apple with `notarytool`, requires an `Accepted` result,
staples the ticket, validates the stapled app, and runs `spctl --assess`. If Apple Notary stalls or
rejects the app, the release workflow fails instead of publishing an unnotarized artifact.

`scripts/notary-status.sh` remains read-only tooling for existing submissions and debugging. See
`docs/NOTARIZATION.md`.
