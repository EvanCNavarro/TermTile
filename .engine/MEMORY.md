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
