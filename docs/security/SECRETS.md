# Secrets

Use environment variables for configuration and keep sensitive values out of source control.

## Local Files

- `.env`, `.env.*`, `.dev.vars`, and `.dev.vars.*` are local-only and must stay ignored.
- `.env.example` may list required names, but it must not contain real secret values.
- Prefer one local secret file style per Cloudflare Worker. Cloudflare documents that `.dev.vars` and `.env` have different loading behavior.

## Cloudflare secrets

Use Cloudflare secrets for sensitive Worker values. Do not put sensitive values in Wrangler `vars`.

Source: https://developers.cloudflare.com/workers/configuration/secrets/

## GitHub secrets

Use GitHub secrets only for CI/CD values that are required by a workflow. Future workflows must use least-privilege permissions and avoid exposing secrets to untrusted pull request contexts.

Source: https://docs.github.com/en/actions/reference/security/secure-use

## Reproducible installs

Once dependencies exist, prefer frozen installs in CI. `npm ci` requires a lockfile and fails instead of updating package manifests when the lockfile does not match.

Source: https://docs.npmjs.com/cli/v9/commands/npm-ci/
