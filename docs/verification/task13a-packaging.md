# Task #13a verification — App bundle + packaging script + packaged-app launch smoke (2026-07-03)

Plan: `.engine/state/stoke-plan-13a.md` (S2, skeptic-audited SAFE-WITH-FIXES; 3 MAJOR fixes folded).
First sibling of the #13 split (#13a local packaging · #13b GitHub-Actions CI · #13c Apple-cert
signing). Turns the bare SPM binary into a distributable, ad-hoc-signed `dist/TermTile.app`
menu-bar bundle + a foreign-path launch smoke + script-invariant tests. Authority:
`docs/research/remembar-audit.md` COPY/ADAPT table.

## Deliverables
- `scripts/build-app.sh` — `swift build -c release --show-bin-path` → assemble
  `dist/TermTile.app/Contents/{MacOS,Resources}` → `plutil -lint`ed Info.plist heredoc → `xattr -cr`
  → inside-out ad-hoc `codesign -s -` (no `--deep`) → `codesign --verify --deep --strict`. Prints the
  .app path as the last stdout line. Env-overridable (APP_NAME/BUNDLE_ID/CONFIGURATION/SHORT_VERSION/
  DIST_DIR/ICON_SRC) so e2e/CI reuse the same build path.
- `scripts/test-packaged-app.sh` — bundle invariants (plist keys via `plutil -extract`, executable
  present, `codesign --verify --deep --strict`, Bundle.module-outside-DEBUG regression guard) + a
  `kill -0` foreign-path launch proof. Only ever kills the ONE pid it spawned (no pkill/killall).
- `Tests/TermTileKitTests/PackagingScriptsTests.swift` — 6 "scripts-as-text" invariants, each a
  POSITIVE, line-scoped, ALL-matches assertion (never first-match, never bare-absence).

## Info.plist keys (from AppIdentity — one source of truth)
`CFBundleIdentifier=dev.ecn.apps.termtile`, `CFBundleName=TermTile`, `CFBundleExecutable=TermTile`,
`CFBundlePackageType=APPL`, `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=28`
(`git rev-list --count HEAD` — monotonic, NEVER dots-stripped, audit §8.5), `LSMinimumSystemVersion=14.0`,
`LSUIElement=true` (menu-bar only), `NSPrincipalClass=NSApplication`, `NSHighResolutionCapable=true`.

## Test evidence (red-first)
- Baseline green: `swift test` → 122; with the new suite → **128 tests passed**.
- Red-first: the 6 assertions failed with 15 issues while the scripts were absent (positive checks —
  `codesign … -s -`, `git rev-list --count`, `--show-bin-path`, `kill -0` — all missing).
- **Invert-check** (FL-1, single flip, separate commands per TRAP-9; `--filter codesignFlagsAreCorrect`
  by FUNCTION name per TRAP-16): added `--deep` to the bundle sign line →
  `✘ Expectation failed: signLines.allSatisfy { !$0.contains("--deep") }` → restored → re-green.
  NOTE: the first invert FALSE-PASSED because the assertion inspected only the first sign line;
  strengthened to `allSatisfy` over ALL sign lines, then the invert reddened correctly.

## Live-surface PROVE (real .app; bundle-specific per skeptic F3)
1. `scripts/build-app.sh` → `dist/TermTile.app` (rc=0); `Info.plist: OK`; inside-out ad-hoc sign.
2. `codesign --verify --deep --strict dist/TermTile.app` → **rc=0**; `codesign -dv` →
   `Identifier=dev.ecn.apps.termtile`, `flags=0x2(adhoc)`, `TeamIdentifier=not set`.
3. `scripts/test-packaged-app.sh` → `OK: … alive=8/8, crash-reports 0->0`.
4. LIVE launch of `dist/TermTile.app/Contents/MacOS/TermTile` (accessory, no focus):
   - `ALIVE pid=24609`; `ps comm` = `dist/TermTile.app/Contents/MacOS/TermTile` (exec path IS the bundle).
   - **System Events `bundle identifier of PID = dev.ecn.apps.termtile`** — the discriminator: a bare
     binary returns *missing value*; the bundled inner exec resolves `Bundle.main`/LaunchServices to
     the enclosing `.app`. This is what makes the proof bundle-specific (not a re-run of task #1).
   - AX `menu bar 2` status item present (MenuBarExtra registered, AX-enumerable).
   - CGWindowList `id=80672 layer=25 bounds=[X:-4777,Y:0,W:72,H:37]` (NSStatusWindowLevel; parked
     off-screen by a menu-bar manager — TRAP-1, existence proven by AX+layer, NOT pixels).
   - Terminated cleanly (own pid); /tmp scratch removed via `rm -f` (TRAP-4).
5. Archival screencapture: `docs/verification/task13a-bundle-launch.png` (NON-proof, TRAP-1).

## Checks
All 10 `.engine/checks/*.sh` PASS, incl. the NEW `scripts-ascii-only.sh` (TRAP-18: a non-ASCII byte
glued to `$var` breaks Bash under `set -u`; fail-closed, bait-tested on a COPY).

## Deferred (real [DEP], not lazy)
- CI live-run (swift test workflow gating build + SwiftLint/Semgrep + release.yml with VirusTotal +
  attestation + SHA-256) → **#13b** [DEP: no-network/no-push in loop beats — provable only on GitHub
  Actions runners with secrets].
- Stable Developer-ID / self-signed signing identity so `.app` TCC grants survive rebuilds → **#13c**
  [DEP: zero codesigning identities on this machine — Developer ID needs an Apple account (network),
  a self-signed identity needs Keychain UI — un-doable offline].
- Icon (sips/iconutil): the script has an OPTIONAL icon step (no-op if no `Resources/AppIcon.png`);
  a menu-bar `LSUIElement` app has no dock icon → YAGNI this beat.
