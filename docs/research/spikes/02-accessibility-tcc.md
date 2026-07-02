# Spike 02 — Accessibility TCC: detect + prompt (task #2)

Observed on: Apple Swift 6.0.3, macOS 15.1 (24B83), arm64. Probe code:
`Sources/AXProbe/main.swift` (throwaway-quality, committed per Phase A contract);
tested wrapper for the real app: `Sources/TermTile/AccessibilityTrust.swift`.

## Questions → observed answers

### 1. Can a plain SPM binary detect AX trust?
Yes. `import ApplicationServices` needs zero linker/platform settings in Package.swift.
The ONLY shape that compiles under Swift 6 strict concurrency (the SDK imports
`kAXTrustedCheckOptionPrompt` as `public var … : Unmanaged<CFString>`, a mutable global):

```swift
@preconcurrency import ApplicationServices
let key: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
let trusted = AXIsProcessTrustedWithOptions([key: false] as CFDictionary)
```

Plain `import` fails with "not concurrency-safe"; using the constant directly as a
dictionary key fails with `Unmanaged<CFString>` vs `AnyHashable`.

### 2. How does trust behave for an unsigned dev binary vs a bundled .app?
Same binary, opposite results — TCC attributes to the **responsible process**:

| Context | Observed | TCC side effect |
|---|---|---|
| `.build/debug/AXProbe` exec'd from shell | `trusted=true` | none — no per-binary row created |
| Same binary in `/tmp/AXProbe.app` via `open` | `trusted=false` | even `prompting:false` registered a DENIED row |

Shell-exec inherits the terminal chain's grant (system TCC.db: `com.apple.Terminal`,
`com.github.wez.wezterm`, `com.googlecode.iterm2` all `auth_value=2` on this Mac).
The bundle is its own responsible process → untrusted, and merely *calling* the
options API registered `dev.ecn.spike.axprobe|auth_value=0` in the SYSTEM TCC.db
(`/Library/Application Support/com.apple.TCC/TCC.db` — Accessibility rows live there,
not in the user db) with csreq decoding to `cdhash H"3a53000c…"` — the exact CDHash
of the binary. **cdhash pinning observed directly, not inferred.**

### 3. Does the ad-hoc cdhash really reset the grant every rebuild? (audit §6 claim)
Nuanced. SPM/linker ad-hoc signs automatically (`Signature=adhoc`). Observed cdhash
behavior across rebuilds of identical output path:
- touch-only rebuild → **identical** cdhash (`b74335…` ×2)
- comment-only edit → **identical** cdhash (deterministic codegen)
- functional edit → **new** cdhash (`683576…`)
- revert to byte-identical source → **different again** (`3a5300…` ≠ original `b74335…`
  — incremental-build artifacts leak into the binary)

Engineering conclusion: determinism is not dependable; **treat any rebuild as voiding a
cdhash-pinned grant** (audit §6's direction is right, its "every rebuild" is merely
over-broad in the no-op case, and the revert case shows you can't rely on that).

### 4. Prompt path (`prompting: true`)
Compiled and committed (`AXProbe --prompt`, `AccessibilityTrust.isTrusted(prompting:)`)
but NOT live-fired. Two observed reasons: (a) from the shell this context is already
trusted, so the prompt cannot fire; (b) from a bundle, even the non-prompting call
pollutes TCC, and per-identifier cleanup FAILS for /tmp bundles (`tccutil reset
Accessibility dev.ecn.spike.axprobe` → OSStatus -10814) — a prompted bare entry would
be worse. Live prompt UX observation belongs to #12's bundled-app permission work
[DEP: shape — prompt is only meaningful from the real .app identity].

### 5. Dev-loop pain verdict + Developer ID timing
- **Phase A/B spike + engine development from a trusted terminal: ZERO TCC pain.**
  All AX spikes (#3–#7) can run as shell-exec'd debug binaries with full trust and no
  per-build grants. This unblocks #3 immediately.
- Pain begins exactly at **bundled-.app testing**: each .app build gets a cdhash-pinned
  grant that the next build voids (re-grant every build).
- **Decision: land a stable signing identity (Developer ID, or minimally a self-created
  signing cert) WITH #13 packaging, before #14's E2E loop** — #14 requires a granted
  .app across repeated builds; without a stable identity every E2E iteration needs a
  manual re-grant. No need to buy/configure it during Phase A/B.

## Residual state on this Mac (expected, inert)
Two denied (`auth_value=0`) Accessibility rows remain in the system TCC.db from probing:
`dev.ecn.apps.axprobe-audit` (plan-audit run) and `dev.ecn.spike.axprobe` (this spike).
Both binaries are deleted; the rows grant nothing and are individually removable only
via `sudo sqlite3 … DELETE` (tccutil per-identifier fails for /tmp bundles).

## Incidental corroboration
`bobko.aerospace` sits granted (`auth_value=2`) in the same TCC class on this Mac —
the AeroSpace tiler uses exactly this permission model (matches
`docs/research/macos-tiling-research.md:20`).

## Repo-facing consequences
- Bare `swift run` now errors ("multiple executable products available"); use
  `swift run TermTile` or `swift run AXProbe`. Loop signals unaffected
  (`swift build` / `swift test` only).
- Accessibility needs NO Info.plist usage-description key (audit §4 confirmed; none added).
