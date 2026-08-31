# TermTile .engine memory

- **Live-surface semantics (native app, not web):** every Swift source under `Sources/` is
  mapped to `subprocess_globs` because the app's real surface is AX manipulation of OTHER
  apps' windows. PROVE (FL-1) for a touched Swift file means: run the built app (or a
  compiled harness) against REAL windows of the target app and verify frames/behavior —
  screenshots via `screencapture` count as rendered-reality evidence (FL-9). Chrome
  DevTools / curl verifiers do not apply here; `frontend_globs` is intentionally empty.
- **Test/build signals:** `swift test` / `swift build` at repo root (Package.swift lands
  with the first build task). Until then both signals are expected-red — that is the
  red-first baseline, not a config error.
- **Research authority:** `docs/research/macos-tiling-research.md` (verified deep-research).
  Spec draft: `docs/product/spec-draft.md`. Template app: RememBar at
  `~/Desktop/safari-history-export/BrowserMemoryBar/`.

- **Testing the DEBUG binary vs the packaged app — different UserDefaults domains.** `.build/debug/TermTile`
  has no `Info.plist`, so `UserDefaults.standard` resolves to the **`TermTile`** domain (process name),
  not `dev.ecn.apps.termtile`. Seeding the bundle-id domain and launching the debug binary proves
  NOTHING — the app reads absent keys, falls back to defaults, and behaves correctly-but-inertly,
  which is indistinguishable from broken wiring. Measured 2026-08-31 while proving session tinting;
  it produced a confident wrong "the app does not write" conclusion. Seed `TermTile`, or test the
  packaged `.app`. Evidence: `docs/verification/session-tinting-2026-08-31.md`.
