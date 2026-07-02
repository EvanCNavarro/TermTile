# Threat Model

Project: termtile
Deploy target: cloudflare

## Assets

- Source code and generated project structure.
- Environment values, Cloudflare secrets, and GitHub secrets.
- User data introduced by future product features.
- Cross-agent skill authority and project instructions.

## Trust Boundaries

- Local developer machine to repository files.
- Repository files to agent/tool execution.
- Local env files to Cloudflare runtime secrets.
- Future GitHub Actions runners to repository secrets.
- Future Cloudflare runtime to external services.

## Abuse Cases

- A secret is committed through `.env`, `.env.*`, `.dev.vars`, or `.dev.vars.*`.
- A workflow or agent receives broader permissions than required.
- A copied skill or generated tool instruction silently diverges from the canonical authority.
- Framework adapter output overwrites project-start security or verification docs.

## Current Boundary

This baseline does not prove production security. It creates the security documentation and analyzer surface that later buckets must enforce through CI, dependency, adapter, and deploy checks.
