# Security Policy

## Supported Versions

This project is pre-release until a real app adapter and deploy path are selected. Treat the default branch as the only supported line unless a release process says otherwise.

## Vulnerability Response

Record suspected vulnerabilities in a private issue, security advisory, or direct owner handoff before public disclosure. Include affected files, reproduction steps, data exposure risk, and mitigation status.

## Reference Standards For Future Gates

These references guide future CI and supply-chain buckets. Bucket 2 only creates and verifies the security documentation surface.

- NIST SSDF: https://csrc.nist.gov/pubs/sp/800/218/final
- OWASP SAMM: https://owasp.org/www-project-samm/
- OpenSSF Scorecard: https://scorecard.dev/
- SLSA: https://slsa.dev/

## Required Local Checks

- Run `npm run check` before claiming security-relevant changes are complete.
- Keep dependency, workflow, and deploy security gates visible in project docs until CI is implemented.
