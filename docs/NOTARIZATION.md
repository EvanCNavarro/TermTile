# Notarization Runbook

TermTile already has the paid Apple Developer Program membership, a Developer ID Application
certificate, and App Store Connect API key credentials. Notarization is not the App Store: it is
Apple's malware scan and Gatekeeper ticket flow for Developer ID apps distributed outside the Mac App
Store.

## Current Evidence

- `v0.2.1` ships with Developer ID signing from team `XG9SBNWNXT`. Its release artifact passes the
  strict packaged-app smoke for Developer ID signing and hardened runtime, but `spctl --assess`
  rejects it as unnotarized.
- Old invalid job `992020e6-0535-4119-99f0-33517bfd1939` proved the first submission lacked hardened
  runtime across TermTile and Sparkle executable code. That was fixed before `v0.2.1`.
- Fixed TermTile jobs `ca11052c-2117-4c9f-a3b9-d5453d59a9ed` and
  `868dd795-f6ef-4024-82c1-60b04d487a72` remained `In Progress` after submission.
- Differential job `a4b780fa-92be-4f61-bfc8-5aedd613ada8` submitted a tiny signed `NotaryProbe`
  app using the same Developer ID team and hardened runtime. It also remained `In Progress`, which
  points away from a TermTile bundle-specific defect and toward Apple-side, team/account, or
  first-time processing delay.

Do not create more submissions while those fixed TermTile and `NotaryProbe` jobs are still pending.
More uploads add queue noise without testing a new assumption.

## Read-Only Status Checks

Use `scripts/notary-status.sh` to inspect existing jobs without uploading anything:

```sh
TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8 \
TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID \
TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID \
scripts/notary-status.sh
```

Poll specific submissions:

```sh
TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8 \
TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID \
TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID \
scripts/notary-status.sh \
  ca11052c-2117-4c9f-a3b9-d5453d59a9ed \
  868dd795-f6ef-4024-82c1-60b04d487a72 \
  a4b780fa-92be-4f61-bfc8-5aedd613ada8
```

Fetch logs only when a job is terminal or Apple Support asks for them:

```sh
TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8 \
TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID \
TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID \
TERMTILE_NOTARY_FETCH_LOGS=1 \
scripts/notary-status.sh a4b780fa-92be-4f61-bfc8-5aedd613ada8
```

## Next Actions

1. Poll the existing fixed TermTile and `NotaryProbe` jobs with `scripts/notary-status.sh`.
2. If any fixed job becomes `Accepted`, staple and assess the exact signed artifact that produced the
   accepted job. Rebuilt apps can have different code hashes, so do not assume a ticket for one build
   applies to a fresh rebuild.
3. If all jobs remain `In Progress`, file Apple Developer Support or Feedback Assistant with the job
   IDs above, the team ID `XG9SBNWNXT`, the Developer ID certificate subject, and the observation that
   the minimal `NotaryProbe` app is also stuck.
4. After Apple returns accepted submissions reliably, wire `scripts/notarize-app.sh` into
   `.github/workflows/release.yml` between the Developer ID smoke test and packaging, then cut the
   notarized follow-up release.
