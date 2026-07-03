# Task #13b — CI wiring verification (2026-07-03)

Second sibling of the #13 split (#13a local packaging DONE · **#13b GitHub-Actions CI** · #13c
Apple-cert signing). This beat authored the real CI workflows and proved — to the extent a
no-network/no-push loop beat can — that they are correct. The LIVE GitHub-runner execution is the
external #20 deferral.

## What landed

| File | Change | Purpose |
|---|---|---|
| `.github/workflows/check.yml` | REWRITE (npm → macOS Swift) | `macos-15`; `swift build` + `swift test` + `swiftlint --strict`; keeps `name: Check` + `permissions: contents: read` (REPOSITORY_POLICY.md branch-protection + least-privilege) |
| `.github/workflows/semgrep.yml` | NEW | `p/security-audit` + `p/secrets` on PR + weekly cron |
| `.github/workflows/release.yml` | NEW | tag `v*` → `swift test` gate → **calls** `scripts/build-app.sh` → ditto + SHA-256 → `actions/attest-build-provenance@v4` → VirusTotal (curl + `secrets.VIRUSTOTAL_API_KEY`) → `gh release create` |
| `.swiftlint.yml` | NEW | lints production `Sources` strict-green; excludes throwaway AXProbe + Tests; `force_cast` kept STRICT (scoped inline) |
| `Sources/TermTileKit/AXWindowSystem.swift` | 2 comment lines | `// swiftlint:disable:next force_cast` at the 2 real AX-bridge sites (behavior-inert) |
| `.github/dependabot.yml` | drop npm ecosystem | npm CI removed → npm updates were vestigial; keeps `github-actions` |
| `docs/github/REPOSITORY_POLICY.md` | doc-drift fix | describes the Swift check gate + release/semgrep, not the old `npm run check` |
| `Tests/TermTileKitTests/WorkflowsTests.swift` | NEW (red-first) | 6 line-scoped POSITIVE invariants over the workflow YAMLs + `.swiftlint.yml` |

## PROVE — what a no-network beat can prove (FL-1)

The SUBSTANCE of "swift test in CI" is that the gated commands actually pass on this repo, and the
YAML is well-formed. All proven locally:

- **`swift test` → 134 tests passed** (128 prior + 6 new `WorkflowsTests`). This is exactly the
  command `check.yml` and `release.yml` run.
- **`swiftlint --strict` → rc=0, 0 violations** — exactly the command the lint step runs. The
  `.swiftlint.yml` config was measured to zero from a baseline of 83 default-rule violations; each
  relaxation maps to a real project convention (throwaway AXProbe excluded; geometry single-letter
  names; Swift-6.1 trailing commas). `force_cast` stays a STRICT rule, exempted inline only at the 2
  CFTypeID-guarded AX sites — so any FUTURE unsafe cast in shipped code is still caught.
- **YAML well-formedness** via `ruby -ryaml` on all three workflows + dependabot + `.swiftlint.yml` →
  all parse (`OK`). (Note: ruby psych is YAML-1.1 and models the `on:` trigger key as boolean `true`
  — a parser quirk, not a file defect; GH-Actions schema validation is #20.)
- **Three invert-checks, one per workflow file** (heeds #13a's single-match false-pass lesson):
  - `check.yml`: `swift test` → `npm run check` ⇒ swift-test-gate + npm-absence invariants RED.
  - `release.yml`: `scripts/build-app.sh` → `swift build -c release` ⇒ script-call invariant RED
    (the full-path assertion is not satisfied by the bare `build-app.sh` comments — no vacuous pass).
  - `semgrep.yml`: drop `--config p/secrets` ⇒ pack invariant RED.
  All three restored → `WorkflowsTests` 6/6 green.
- **All 10 `.engine/checks/*.sh` PASS** (core-purity, axprobe-*, scripts-ascii-only, etc.).
- The `AXWindowSystem.swift` change is **behavior-inert** (`git diff` = 2 comment lines only), so no
  live AX re-proof is required; the live AX write/event paths were proven in #19a/#19b and are
  unchanged.

## Deferred → #20 (external)

Live execution on GitHub Actions runners — `check.yml`/`semgrep.yml` green on a PR, and a `v*` tag
driving `release.yml` (build-app.sh → attest → VirusTotal → gh release) with `secrets.VIRUSTOTAL_API_KEY`
configured — plus GH-Actions schema validation (actionlint/yamllint, absent locally + no network to
install). `[DEP: external — needs GitHub runners + a push + configured secrets]`. Release shipping also
needs #13c's stable signing identity.
