# Repository Policy

## GitHub Baseline

Generated git-backed projects include a check workflow, Dependabot configuration, and pull request template. The workflow follows GitHub's least-privilege guidance by setting `permissions: contents: read`. For this Swift package the check workflow runs on a macOS runner and gates the build on `swift build`, `swift test`, and `swiftlint --strict` (the npm placeholder was replaced in #13b). A tag-triggered `release.yml` builds the signed `.app`, attests build provenance, runs a VirusTotal scan, and publishes a GitHub release; a `semgrep.yml` runs the `p/security-audit` and `p/secrets` rule packs on PRs and weekly.

Sources:

- GitHub Actions secure use: https://docs.github.com/en/actions/reference/security/secure-use
- GitHub workflow syntax permissions: https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions
- Dependabot options reference: https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
- Pull request templates: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository

## Branch Protection

When this project is connected to GitHub, require the check workflow before merging to the default branch. Require pull request review for changes that affect security docs, workflow permissions, dependency automation, Cloudflare deploy config, or shared agent instructions.

## Scratch Lab Boundary

This initializer can generate and analyze GitHub files without the scratch lab itself being a git repository. It does not prove branch protection, required checks, or a live GitHub Actions run until the generated project is pushed to a real repository.
