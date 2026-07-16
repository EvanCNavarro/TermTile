# TermTile

**A menu-bar app that tiles your terminal windows into an even grid — one click.**

Pick your terminal app (iTerm2 or WezTerm), press **Rearrange now**, and every visible window snaps
into columns of two, evenly spaced across your screen. No manual dragging, no window-manager to
learn — just a tidy grid on demand.

## What it is

TermTile lives in your menu bar and does one thing well: it arranges a chosen app's windows into a
clean grid (two windows per column, columns added as windows are). It drives macOS's Accessibility
API to move and resize the real windows — so it works with the terminal you already use, and touches
nothing until you ask it to.

- **One target app at a time** — iTerm2 by default; pick any running app from the menu.
- **On-demand** — it only rearranges when you press the button (or a **global hotkey**, ⌘⌥T by
  default, which you can re-record in the menu). Your windows are yours the rest of the time.
- **Adjustable gap** — set the spacing between tiled windows from the menu.
- **Auto-updates** — a built-in **Check for Updates…** keeps you current.
- **Clean uninstall** — an **About** panel with a one-click uninstall that removes the app and its
  data (and tells you the one thing it can't: revoking the Accessibility grant).

## Install

1. Download `TermTile-<version>.zip` from the
   [latest release](https://github.com/EvanCNavarro/TermTile/releases/latest) and unzip it. Drag
   **TermTile.app** to `/Applications`.
2. Double-click **TermTile.app**. v0.2.2 and newer release artifacts are Developer ID signed,
   notarized, and stapled, so Gatekeeper can verify the app before launch. v0.2.1 was the
   transitional Developer ID signed but unstapled release.
3. **Grant Accessibility** so it can arrange windows: **System Settings → Privacy & Security →
   Accessibility → enable TermTile.** TermTile shows a one-click button to this screen when it detects
   access is missing.
4. Click the **TermTile** menu-bar item → pick your terminal in **Target app** → press **Rearrange now**.

Requires **macOS 14 (Sonoma) or later**, on **Apple Silicon**.

## Privacy & permissions

TermTile is local and quiet:

- **It only moves windows.** It reads the target app's window list and frames through the
  Accessibility API and writes new positions back. It never reads window *contents*, your keystrokes,
  or anything you type.
- **No telemetry.** No analytics, no tracking.
- **The only network request** is the update check: TermTile fetches its signed appcast from this
  repository's GitHub releases to see if a newer version exists. Nothing about you is sent.

**Permissions it asks for:** Accessibility (to move and resize windows). That's it.

## Verify this download

Every release is **built by this repository's GitHub Actions** — not a personal machine — and each
release carries what you need to check the file before running it:

- **Build provenance** — confirm the download came from this repo's CI, untampered:
  ```bash
  gh attestation verify TermTile-<version>.zip --repo EvanCNavarro/TermTile
  ```
- **SHA-256** — published as a `.sha256` asset next to the zip; verify with
  `shasum -a 256 -c TermTile-<version>.zip.sha256`.
- **Developer ID signed** — public releases use Apple's Developer ID Application signing so macOS
  Accessibility/Input Monitoring grants keep a stable code identity across updates.
- **Notarized and stapled** — v0.2.2 and newer release artifacts are submitted to Apple Notary,
  stapled, and Gatekeeper-assessed before the zip is created.
- **Signed updates** — the Sparkle auto-update feed is EdDSA-signed, so an update with a missing or
  bad signature is refused.

**Dependabot** keeps the CI action versions current; **Semgrep** and **SwiftLint** run on every push.

## Build from source

```bash
git clone https://github.com/EvanCNavarro/TermTile.git
cd TermTile
scripts/fetch-sparkle.sh          # vendor the Sparkle framework (once)
swift build && swift test         # build + the full test suite
scripts/install-app.sh            # build a signed .app and install to ~/Applications/TermTile
```

Architecture is a functional core / imperative shell (see `docs/decisions/0001-*`): pure layout math
in `TermTileCore`, the Accessibility adapter in `TermTileKit`, a thin SwiftUI menu-bar shell.

## Not yet

- **Intel Macs** — the build is Apple Silicon only for now.
- Multi-display / Spaces awareness is on the roadmap.

## Releasing

See [`docs/RELEASING.md`](docs/RELEASING.md) — version scheme + how to cut a release.

## License

MIT. See [`LICENSE`](LICENSE).
