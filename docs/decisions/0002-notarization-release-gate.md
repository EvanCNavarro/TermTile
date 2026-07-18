# Decision 0002: Notarization Release Gate

## Status

Accepted on 2026-07-16. Updated later the same day after Apple Notary returned `Accepted`.

## Context

`v0.2.1` fixed TermTile's immediate Accessibility/Input Monitoring update breakage by requiring a
Developer ID Application signature for public release artifacts. Its public zip was created before
Apple returned a Notary ticket, so the artifact is Developer ID signed but unstapled.

Apple later returned `Accepted` for the fixed TermTile submissions and the minimal `NotaryProbe`
submission. That removed the queue-status blocker.

## Decision

Gate public release on Developer ID notarization. Keep the Developer ID signing requirement in public
release CI, then run `scripts/notarize-app.sh` before packaging so the release zip contains the
stapled app. Do not publish a public release if Apple Notary fails, stapling fails, or Gatekeeper
assessment rejects the app.

Public Developer ID artifacts must also keep hardened-runtime library validation enabled. Local
self-signed or ad-hoc development builds may use
`com.apple.security.cs.disable-library-validation` so the locally re-signed app can load the embedded
Sparkle framework, but public release artifacts must not carry that entitlement.

## Consequences

- Users get a stable Developer ID code identity in `v0.2.1`, which addresses the TCC grant reset class
  caused by ad-hoc signatures.
- `v0.2.1` remains a transitional signed-but-unstapled release.
- `v0.2.2` and later public releases must be Developer ID signed, notarized, stapled, and
  Gatekeeper-assessed before the zip/checksum/appcast are produced.
- The release smoke test must inspect shipped entitlements and reject
  `com.apple.security.cs.disable-library-validation` on Developer ID artifacts.
