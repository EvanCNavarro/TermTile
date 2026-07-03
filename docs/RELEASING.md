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
the `.app` → zips + checksums → generates the EdDSA-signed appcast with embedded notes → attests
provenance → (optional) VirusTotal → publishes the GitHub Release with the zip, `.sha256`, and
`appcast.xml`. Existing users get the update offered automatically via the `SUFeedURL`.

## Not yet (Option A → B)

Releases are currently **ad-hoc signed** — users right-click → Open past Gatekeeper once. A paid
Apple Developer ID + notarization removes that warning and adds Apple's own malware scan; wire it
by swapping `TERMTILE_SIGN_IDENTITY` and adding a `notarytool`/`stapler` step.
