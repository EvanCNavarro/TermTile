# Decision 0002: Notarization Release Gate

## Status

Accepted on 2026-07-16.

## Context

`v0.2.1` fixed TermTile's immediate Accessibility/Input Monitoring update breakage by requiring a
Developer ID Application signature for public release artifacts. Notarization is prepared, but Apple
Notary submissions using the fixed TermTile bundle and a minimal `NotaryProbe` bundle are still
pending.

## Decision

Do not claim TermTile is notarized and do not gate public release on Notary until Apple returns an
accepted submission for this Developer ID team. Keep the Developer ID signing requirement in public
release CI. Use read-only status checks for the existing jobs instead of creating duplicate
submissions.

## Consequences

- Users get a stable Developer ID code identity in `v0.2.1`, which addresses the TCC grant reset class
  caused by ad-hoc signatures.
- Gatekeeper can still report the release as unnotarized until a future release includes a stapled
  Notary ticket.
- The notarized follow-up release waits on Apple-side status evidence, not another speculative code
  change.
