# Task #12b verification — Launch-at-login: LoginItem port + SMAppService adapter + fake

**Date:** 2026-07-03 · **Branch:** loop/phase-a · **Plan:** `.engine/state/stoke-plan-12b.md` (S2)

## What landed
- `Sources/TermTileKit/LoginItem.swift` — `LoginItemStatus` (domain enum) + `LoginItem` protocol
  (sync `Sendable`: `status`/`register()`/`unregister()`) + `SMAppServiceLoginItem` production
  adapter wrapping `SMAppService.mainApp` (resolves `.mainApp` per call to stay Sendable — the
  `UserDefaultsSettingsStore` F1 fix; explicit named-case `map` with `@unknown default`).
- `Tests/TermTileKitTests/InMemoryLoginItem.swift` — deterministic fake (`final class` + `NSLock` +
  `@unchecked Sendable`; seedable initial status; register/unregister toggle enabled/notRegistered).
- `Tests/TermTileKitTests/LoginItemTests.swift` — 5 tests (keystone mapping + 4 fake-behavior).
- `Sources/AXProbe/main.swift` — `logincheck` verb (external-process liveness read of the real adapter).

## PROVE
### Unit (correctness) — `swift test`
```
✔ Suite "Launch-at-login — LoginItem port" passed
✔ Test run with 112 tests passed after 0.022 seconds.   (107 → 112, +5)
```

### Invert-check (red-first) — the keystone genuinely fails when the mapping is wrong
Swapped `.notRegistered`/`.enabled` arms in `SMAppServiceLoginItem.map`:
```
✘ Expectation failed: (SMAppServiceLoginItem.map(.notRegistered) → .enabled) == .notRegistered
✘ Expectation failed: (SMAppServiceLoginItem.map(.enabled) → .notRegistered) == .enabled
✘ Test "SMAppService.Status maps 1:1 to LoginItemStatus (keystone)" failed with 2 issues.
```
Restored → `✔ ... keystone passed`. An explicit-switch map (not a rawValue bridge) makes this
invert real; a `@unknown default` does not mask the swap (the four cases are explicit arms).

### Live (liveness/smoke ONLY — NOT the correctness proof)
```
$ swift run AXProbe logincheck
logincheck: status=notFound bundleID=none note=liveness-smoke-only-correctness-proven-by-unit-test PASS=true
rc=0
```
The REAL `SMAppServiceLoginItem().status` resolved through real ServiceManagement from an external
process, returned `.notFound` (expected: an unbundled ad-hoc binary is not a registered, signed
login item — Apple documents `SMAppService` callers "must be code signed"), no crash/no hang. This
touches only 1 of 4 statuses — it proves the READ path is wired to the system, NOT that the mapping
is correct (the unit test proves correctness).

### DEFERRED to #13 (real dependency, not a dodge)
LIVE `register()`/`unregister()` — real login-item registration — is un-exercisable without #13's
packaged, code-signed `.app` + login-item domain (`kSMErrorInvalidSignature` from an unsigned
binary). Recorded as `[DEP: blocked-by #13 …] → #13`.

## Fail-closed checks
core-purity, axprobe-no-defer, axprobe-detached-task, no-iterm-whose-filter, task-refs-int-keys,
traps-ordered, cwc-config-present, reorient-next-task-cited — all PASS.
