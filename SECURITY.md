# Security Policy

## Supported versions

The **latest [release](https://github.com/EvanCNavarro/TermTile/releases/latest)** is the supported
line. Fixes ship in a new release; there are no back-ported patch branches.

## Reporting a vulnerability

Please report privately via a
[GitHub security advisory](https://github.com/EvanCNavarro/TermTile/security/advisories/new) rather
than a public issue. Include affected version, reproduction steps, and the impact (what an attacker
gains). You'll get an acknowledgement and, once fixed, a released version.

## What TermTile can and can't touch

TermTile uses the macOS **Accessibility** API to move and resize a chosen app's windows. It reads
window lists and frames and writes new positions — it does **not** read window contents, keystrokes,
the clipboard, files, or the network. Its only outbound request is the signed update check (fetching
the appcast from this repo's releases). There is no telemetry.

## Supply-chain integrity

- **Releases are built by this repo's GitHub Actions**, not a personal machine.
- **Build provenance attestation** — verify a download came from this repo's CI untampered:
  `gh attestation verify TermTile-<version>.zip --repo EvanCNavarro/TermTile`.
- **SHA-256** checksum published beside each release zip.
- **EdDSA-signed auto-updates** — Sparkle refuses an update whose signature doesn't verify against
  the public key baked into the app.
- **Dependabot** keeps CI action versions current; **Semgrep** (`p/security-audit`, `p/secrets`) and
  **SwiftLint** run on every push.

## Known limitations

Releases are currently **ad-hoc signed, not notarized** — macOS Gatekeeper shows an "unidentified
developer" warning on first launch (see the README install steps). A Developer ID + notarization —
which adds Apple's own malware scan and removes the warning — is planned for public distribution.
