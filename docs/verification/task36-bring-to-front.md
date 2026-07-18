# Task #36 verification - optional bring-to-front on Rearrange

**Date:** 2026-07-17; refreshed 2026-07-18 after the Target/Rearrange grouping polish,
final reviewer fixes, and identity-authority cleanup.

## What This Proves

The manual Rearrange command now preserves the old no-focus behavior by default, and can optionally
ask macOS to bring the selected target app forward after tiling. The implementation stays in the
existing functional-core / imperative-shell shape:

- `AppSettings` owns the persisted `bringToFrontOnRearrange` user preference.
- `MenuBarViewModel.rearrangeNow()` remains the single command path for the menu button, global
  hotkey, and `TERMTILE_TILE_ONCE`.
- `TargetAppForegrounding` is the injected foregrounding port.
- `TargetRunningApplicationResolver` is the shared selected-app process resolver used by both AX
  tiling and AppKit foregrounding, so they prefer the same regular app process for a bundle id.
- `WorkspaceTargetAppForegrounder` is the only production AppKit adapter for target-app activation.
- The production adapter uses public `NSRunningApplication.activate(options:)` with
  `.activateAllWindows`. It does not use deprecated `ignoringOtherApps` behavior or private
  window-server APIs.
- Gallery and selftest compositions do not inject the production foregrounder.

## Test Evidence

Targeted red-first suites:

- `swift test --filter SettingsStoreTests`
- `swift test --filter MenuBarViewModelTests`
- `swift test --filter TargetAppForegrounderTests`
- `swift test --filter TargetRunningApplicationResolverTests`
- `swift test --filter MenuBarContentAccessibilityTests`
- `swift test --filter appOwnedActivationAvoidsIgnoringOtherApps`
- `swift test --filter tilingAndForegroundingShareTargetAppResolution`
- `swift test --filter updateDialogUsesSharedAppIdentity`
- `swift test --filter inFlightRearrangeDoesNotForeground`
- `swift test --filter inFlightForegroundResultDoesNotRepopulate`
- `swift test --filter localAppSignatureAllowsEmbeddedSparkleWithoutWeakeningDeveloperIDReleases`

Full health gate after reviewer fixes:

```sh
swift build && swift test && swiftlint --strict
```

Result: build passed, **226 tests passed**, SwiftLint reported **0 violations**.

Additional packaged-app due diligence caught a hardened-runtime/Sparkle library-validation failure in
the local self-signed app bundle. `scripts/build-app.sh` now uses one app-signing path, disables
library validation only for local non-Developer-ID builds by default, and keeps Developer ID release
builds on the stricter hardened-runtime path unless explicitly overridden.
`PackagingScriptsTests.localAppSignatureAllowsEmbeddedSparkleWithoutWeakeningDeveloperIDReleases`
guards that build-script invariant, and Developer ID packaged-smoke mode now rejects shipped artifacts
that carry `com.apple.security.cs.disable-library-validation`.

```sh
scripts/build-app.sh
scripts/test-packaged-app.sh dist/TermTile.app
```

Result: the packaged app launched and stayed alive under `TERMTILE_GALLERY=1`.

## Live UI Evidence

The native gallery path was launched from the debug binary:

```sh
TERMTILE_GALLERY=1 .build/debug/TermTile
```

The process emitted `GALLERY shown`. `CGWindowListCopyWindowInfo` then found the real gallery window:

```text
owner=TermTile name=TermTile - panel (gallery) layer=0 bounds={ Height = 667; Width = 280; X = 714; Y = 174; }
```

Captured via the window server:

```sh
screencapture -x -l 21571 docs/verification/task36-bring-to-front-gallery.png
```

Artifact: [task36-bring-to-front-gallery.png](task36-bring-to-front-gallery.png)

This proves the new `Bring app forward` toggle renders in the real SwiftUI/AppKit gallery window
with native controls. The final grouping is:

- `Target`: selected app.
- `Rearrange`: manual-command options, including gap, app focus, and shortcut.
- `Drag`: drag-reorder behavior and strategy.
- `General`: app lifecycle settings.

The capture does not rely on `ImageRenderer`, which renders native AppKit controls as placeholders
in this panel.

## Live Foregrounding Evidence

Calculator was used as a harmless normal GUI target app. The proof moved focus to Finder, then issued
the same public activation primitive used by `WorkspaceTargetAppForegrounder`:

```swift
target.activate(options: [.activateAllWindows])
```

The system accepted the request and the target owned the top normal visible window afterward:

```text
RESULT accepted=true before=com.apple.finder after=com.apple.finder targetActive=false topPID=30290 targetPID=30290 verified=true
```

`NSWorkspace.frontmostApplication` remained stale as Finder in this run, so the production verifier
checks three public signals: target app active, workspace frontmost bundle, or the target process
owning the top normal visible layer-0 window.

## Code Review Findings Addressed

- Foregrounding is gated on current Accessibility trust after `refreshTrust()`, so hotkey and
  one-shot command paths cannot steal focus when rearranging is unavailable.
- `TargetForegroundResult` is recorded on `MenuBarViewModel.lastForegroundResult`; rejected,
  unverified, and not-running outcomes now render a compact warning in the `Rearrange` group.
- Tiling and foregrounding now use the same `TargetRunningApplicationResolver`, avoiding separate
  bundle-id process selection rules for apps with helper/background or same-bundle processes.
- In-flight foreground completions are generation-guarded, so changing the target, disabling the
  focus option, or starting a newer Rearrange cannot repopulate a stale focus warning.
- The same freshness guard now runs before `foregrounder.bringToFront`, so a Rearrange that becomes
  stale while tiling is still awaiting cannot bring the old target app forward.
- Local packaged builds can load embedded Sparkle without weakening Developer ID release artifacts.
- Developer ID release smoke now inspects shipped entitlements and rejects the local-only
  library-validation entitlement.
- Existing app-owned alert/gallery activation now uses `NSApplication.shared.activate()` instead of
  deprecated `activate(ignoringOtherApps:)`.
- The MacFaceKit update adapter reads the app name from `AppIdentity.appName`, keeping TermTile's
  name at the existing app-identity authority instead of duplicating a literal at the adapter edge.

## Honest Scope Boundary

This does not claim that macOS will always move another app frontmost across Spaces, fullscreen
contexts, or other window-manager policies. The production adapter reports `.frontmost`,
`.requestAcceptedButUnverified`, `.notRunning`, or `.activationRejected` so those OS outcomes remain
observable instead of being treated as guaranteed.
