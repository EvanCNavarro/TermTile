# Live App Polish Verification - 2026-07-18

Scope: post-v0.2.6 local candidate polish for top-right update indicators, stale-permission recovery,
and zoom-safe drag-reorder.

This verification intentionally did not create a TermTile public release tag or run the public release
pipeline.

## Dependency Gate

- MacFaceKit `v0.4.2` (`c430176469758fa465d2d3d9399859c9467bfd6e`) was tagged from the real
  MacFaceKit repo and consumed through SwiftPM. It includes the `v0.4.1` top-right attention behavior
  plus action-capable `NoticeCard`/`LinkButton` support for stale-permission recovery.
- MacFaceKit validation:
  - `swift build` - pass
  - `swift test` - pass, 41 tests
  - `swiftlint --strict` - pass, 0 violations

## TermTile Gate

- `scripts/fetch-sparkle.sh` - pass, Sparkle already vendored.
- `swift build` - pass.
- `swift test` - pass, 273 tests.
- `swiftlint --strict` - pass, 0 violations.
- Focused red-first coverage added for:
  - title-bar zoom/resize gestures not firing drag-reorder;
  - menu-bar glyph upper-right orange pixels;
  - MacFaceKit `IconButton` upper-right attention placement;
  - single visible settings action in permission notices;
  - stale Accessibility reset without spawning the prompt-backed trust request;
  - stale Input Monitoring reset plus current-app re-registration from the single visible notice action;
  - installer relaunch waiting/retry behavior after a live LaunchServices `-600` race;
  - installer cleanup of both old `~/Applications/TermTile` and `~/Applications/TermTile.app` paths;
  - gallery-only forced update attention for native visual proof without downgrading.

## Installed Local Candidate

Command:

```sh
SHORT_VERSION=0.2.7 TERMTILE_BUILD_NUMBER=146 scripts/install-app.sh
```

Installed bundle:

- Path: `/Applications/TermTile.app`
- `CFBundleShortVersionString`: `0.2.7`
- `CFBundleVersion`: `146`
- `LSUIElement`: `true`
- `SUEnableAutomaticChecks`: `false`
- Signing identity: `TermTile Dev Signing`
- `codesign --verify --deep --strict /Applications/TermTile.app` - pass
- `scripts/install-app.sh` initially exposed a transient LaunchServices `-600` relaunch race. The script
  now waits for the old process and retries with `open -n`; the invariant is covered by
  `PackagingScriptsTests`.
- Code review found the old `~/Applications/TermTile.app` migration path was not removed. The installer
  now removes both `~/Applications/TermTile.app` and the legacy extensionless `~/Applications/TermTile`
  path before registering `/Applications/TermTile.app`.

Packaged smoke:

```sh
scripts/test-packaged-app.sh /Applications/TermTile.app
```

Result:

```text
OK: /Applications/TermTile.app launched, rendered gallery, armed update probe, and stayed alive (pid=1881, alive=8/8, crash-reports 0->0)
```

Post-smoke check: `/Applications/TermTile.app/Contents/Info.plist` still existed and reported
`CFBundleVersion` `146`.

## Native Screenshot Proof

No downgrade was installed for these screenshots. The installed candidate is `0.2.7`, so it is expected
not to show a real Sparkle update indicator against the current public `0.2.6` appcast. For visual proof
of the indicator, the native gallery was launched with a gallery-only hook that writes through the single
`Updater` availability source:

```sh
TERMTILE_SELFTEST=1 \
TERMTILE_GALLERY=1 \
TERMTILE_GALLERY_UPDATE_AVAILABLE=1 \
TERMTILE_GALLERY_BROKEN=1 \
/Applications/TermTile.app/Contents/MacOS/TermTile
```

WindowServer reported:

- `TermTile - panel (gallery)` at layer `0`
- two TermTile status items at layer `25`

Artifacts:

- `docs/verification/live-app-polish/gallery-update-permission-2026-07-18.png`
- `docs/verification/live-app-polish/status-item-a-update-2026-07-18.png`
- `docs/verification/live-app-polish/status-item-b-update-2026-07-18.png`
- `docs/verification/live-app-polish/stale-accessibility-reset-2026-07-18.png`

Native screenshots observed:

- The gallery ellipsis update dot is on the top-right of the button.
- The stale-grant permission notice renders one action, `Reset & Open Settings`, as a button-like action.
  It clears TermTile's old Accessibility row before opening Settings and does not spawn the extra macOS
  permission prompt dialog.
- The permission text and action label fit without truncation in the native gallery window.
- Status item A showed a top-right orange dot.
- Status item B showed no orange dot, expected for the normal `0.2.7` candidate process.

Source/test-backed coverage, not shown in the stale-Accessibility screenshot:

- The Input Monitoring notice uses one button-like `Allow Input Monitoring` action that clears stale
  `ListenEvent` rows, re-registers the current app through the Input Monitoring request path, then opens
  Settings. This keeps the app approvable after a stale row is reset without adding a second visible
  repair button.

Pixel check:

```text
status-item-a-update-2026-07-18.png: size=76x72 orange=159 bbox=x46...59,y17...30 upper=true right=true
status-item-b-update-2026-07-18.png: orange=0
```

`chromwebdevtools` was not applicable here because TermTile is a native SwiftUI/AppKit menu-bar app with
no browser surface. Native WindowServer screenshots are the relevant UI proof.
