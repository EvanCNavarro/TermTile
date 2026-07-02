# termtile

Framework adapter: none
Deploy target: cloudflare

Run `npm run check` after setup changes.

## Why these files exist

- `AGENTS.md` is the shared agent instruction authority.
- `CLAUDE.md` imports `AGENTS.md` and contains only Claude-specific deltas.
- `.engine/` stores portable project memory and Locomotion-facing config.
- `.skills/manifest.json` records the canonical cross-agent skill source and adapter paths.
- `docs/environment/` documents macOS, terminal, tmux, and command portability expectations.
- `SECURITY.md` and `docs/security/` define vulnerability, threat-model, and secrets handling.
- `.github/` defines git-backed project automation templates; `docs/github/` explains what this scratch initializer can and cannot prove locally.
- `docs/setup/` records adapter and environment setup notes.
