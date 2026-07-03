# Agent Instructions

## Repository Expectations

- Run `swift build && swift test && swiftlint --strict` before claiming project health.
- Keep secrets out of commits.
- Put durable decisions in `docs/decisions/`.
- Keep generated caches out of source control.
- Treat macOS, tmux, and command portability expectations in `docs/environment/` as part of the project contract.
- Treat `.skills/manifest.json` as the project-readable cross-agent skill authority.
