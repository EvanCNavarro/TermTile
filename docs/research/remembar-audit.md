# RememBar Audit → TermTile Inventory (2026-07-02)

Source project: `~/Desktop/safari-history-export/BrowserMemoryBar/` (read-only audit).
All claims verified against file contents by the audit agent.

## 1. Package.swift

`swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`.

- One `.executableTarget(name: "BrowserMemoryBar", dependencies: ["Sparkle"], resources: [.process("Resources")])` exposed as `.executable(name: "RememBar")` — internal target name and marketing name deliberately decoupled.
- Sparkle vendored as a **local binaryTarget** (SPM's remote artifact downloader hangs in some sandboxes; `scripts/fetch-sparkle.sh` vendors it into gitignored `Vendor/`).
- **Linker rpath trick** (load-bearing for any embedded framework): `.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])` — "Linking Sparkle WITHOUT this + the embed = dyld crash."
- Test target `@testable import`s the executable target directly — no library split.

**Transfers:** tools-version 6.0 layout, platform pin, exec+test target shape, `.process("Resources")`. **Doesn't transfer initially:** binaryTarget + rpath (Sparkle-specific; re-add both *atomically* later). AX needs just `import ApplicationServices`.

## 2. scripts/

### `build-remembar-app.sh` (137 lines) — the crown jewel
- `xattr -cr` before signing; **ad-hoc, inside-out signing — no `--deep`** (per Sparkle docs: sign XPC services/helpers individually, `--deep` can corrupt XPC signatures); final `codesign --verify --deep --strict`.
- Version scheme: `SHORT_VERSION` env-overridable; `CFBundleVersion` = dots-stripped (`0.3.2 → 032`).
- Everything env-overridable (`CONFIGURATION`, `REMEMBAR_VERSION`, `REMEMBAR_DIST_DIR`, feed URL, pubkey, icon) — this is what lets e2e/demo/CI reuse the same build path.
- **Notarization: none.** Deliberately deferred; ships ad-hoc signed with README "Open Anyway" walkthrough. "Virus testing" = VirusTotal upload in CI.

### `test-packaged-app.sh` (71 lines) — highest-value transferable script
Proves a packaged .app launches on a machine that is NOT the build machine. Born from the 0.3.0 shipping crash ("Bundle.module's generated accessor has a hardcoded absolute .build path baked in at compile time... a locally-built .app can appear healthy even when a required resource was never packaged"). Steps: release build → grep no source touches `Bundle.module` outside the DEBUG-guarded helper → assert required resources in `Contents/Resources` → **move every local `.build/*.bundle` aside** (trap-restored) so the baked-in path can't mask a gap → launch raw executable, poll `kill -0` ~4s, diff crash-report counts in `~/Library/Logs/DiagnosticReports/`.

### `smoke-remembar-diagnostics.sh`
JSONL-diagnostics smoke: launch with diagnostics dir overridden, assert session-start event, SIGKILL, relaunch, assert unclean-exit breadcrumb. Safety detail: refuses to run if the app is already up (`pgrep -x`), never `pkill`s globally — and a unit test PINS that property (ScriptWorkflowTests asserts scripts contain no `pkill`/`killall`).

### `test-update-e2e.sh` / `demo-update.sh` / `fetch-sparkle.sh`
Sparkle pipeline (appcast generation, deterministic Ed25519 signature check, embedded release notes, scratch-dir guards). SKIP until TermTile adds updates; then copy wholesale.

### `.github/workflows/release.yml` — where "virus testing" lives
Tag `v*` → macos-15 runner: fetch-sparkle → same build script → re-verify packaged-resource invariants in CI → `ditto` zip + SHA-256 → appcast (Ed25519 private key from `secrets.SPARKLE_ED_PRIVATE_KEY`) → **VirusTotal scan** (`secrets.VIRUSTOTAL_API_KEY`, analysis URL into release notes) → `actions/attest-build-provenance@v4` → `gh release create` with a "Verify this download" section (SHA-256, VT link, `gh attestation verify` command). Plus `swiftlint.yml`, `semgrep.yml` (`p/security-audit` + `p/secrets`, weekly), dependabot (github-actions, `ci` prefix).

## 3. App bundle construction (SPM binary → .app)

1. `swift build` → locate via `--show-bin-path` → copy to `Contents/MacOS/`.
2. Manually copy runtime resources to `Contents/Resources/` (Bundle.main in release; `BundleResources.swift` tries `Bundle.main` first, `Bundle.module` only `#if DEBUG` — omitting a resource crashed 0.3.0).
3. Icon: `sips` one 1024px PNG → 10-entry `.iconset` → `iconutil -c icns`.
4. Info.plist generated as heredoc, `plutil -lint`ed. Keys: **`LSUIElement: true`** (menu-bar only), `NSPrincipalClass: NSApplication`, `LSMinimumSystemVersion: 14.0`, `CFBundleIconFile`, Sparkle SU keys.
5. `ditto` Sparkle.framework into `Contents/Frameworks/` (pairs with rpath).
6. Script prints .app path as last stdout line so callers `tail -1`.

Steps 1–4 + 6 transfer nearly verbatim (drop SU keys + step 5). Note: Accessibility (AXIsProcessTrusted) needs **no plist usage-description key**, unlike some TCC classes.

## 4. Test suite

18 files, 4,602 lines, **182 `@Test` functions** using **Swift Testing** (`@Suite`, `#expect`/`#require`), not XCTest.

- **Pure-function extraction, systematically**: `MenuBarWindowPlacement` is a pure enum over CGRects (no AppKit) — the exact shape for TermTile's tiling math (`enum TileLayout { static func frames(for count: Int, in visibleFrame: CGRect) -> [CGRect] }`) with a thin AX shim around it.
- Protocol seams + `TestDoubles.swift` (fixed/slow fakes).
- **Offscreen render-to-PNG tests** of real production SwiftUI views ("a visual proof"), archived in `design/renders/`.
- **Scripts unit-tested as text** (invariants pinned: `--show-bin-path` present, no `pkill`).
- Security regression suite pins each fixed leak vector.
- Anti-flake: `eventually(attempts:interval:)` polling helper instead of fixed sleeps.
- **Gap: tests do NOT run in CI** — only lint/semgrep/release workflows exist.

## 5. Menu bar app architecture

- Pure SwiftUI `@main` App with `MenuBarExtra { ... } label: { ... }`, `.menuBarExtraStyle(.window)` — no hand-rolled NSStatusItem.
- `@NSApplicationDelegateAdaptor` only for `applicationWillTerminate`. Gotcha recorded: the SwiftUI adaptor never calls `applicationDidFinishLaunching` — `init()` is the reliable hook (DEBUG env hooks wired there via `DispatchQueue.main.async`).
- Settings persistence: none (hand-edited JSON). Paths centralized in `RememBarPaths.swift` ("single authority for identity and on-disk footprint", carries historical bundle IDs from a rename).
- Launch-at-login: absent. No hotkeys despite README.
- Extras worth porting: one-click uninstaller with Finder-reveal fallback; menu-bar-window offscreen guard (pure math); DEBUG-only Gallery window (`REMEMBAR_GALLERY=1`, flips activation policy since LSUIElement apps have no windows); JSONL crash-breadcrumb diagnostics with unclean-exit detection.

## 6. Permissions handling

RememBar needs Full Disk Access, not Accessibility — the *pattern* transfers:
- Detection by **probing**, not API flag; error classified via NSCocoa/POSIX permission codes.
- Deep link to the exact Settings pane: `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` → TermTile uses `...?Privacy_Accessibility` + `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, same "blocked status row with fix-it button" UX.
- **Critical lesson (TODO.md:20–27): ad-hoc signing makes the TCC designated requirement the per-build cdhash — every update RESETS the TCC grant.** For an AX-dependent tiler this is a hard UX failure; budget a stable signing identity (Developer ID) earlier than RememBar did.

## 7. Release process & conventions

- SemVer tags `vX.Y.Z`; tag push cuts the release; release notes authored pre-tag in `release-notes/<version>.md` (single source for Sparkle "What's new" + GitHub Release body).
- TODO.md with decision-rationale blocks; CLEANUP-PLAN with DO/GATE/SKIP verdicts and "no number, no merge" measurement ethos.
- RememBar's `.engine/traps.md` lessons that apply here: linking≠embedding, SPM binary-downloader hang, `NSApplication.shared` never `NSApp.x` in test context, flatten history before first public push, `eventually{}` for timing-flaky tests.

## 8. Improvement opportunities for TermTile

1. `swift test` in CI + release gated on it (RememBar's biggest gap).
2. Run the packaged-app launch smoke in CI, not just locally.
3. CI should call the scripts (RememBar duplicates checks in release.yml → drift risk).
4. Copy resources by manifest/glob, or assert copied-set == source-set (the 0.3.0 bug class).
5. Proper monotonic build number (dots-stripped collides past single digits: `1.0.0 → 100` vs `0.10.1 → 0101`); use padded fields or commit count from day one.
6. Launch-at-login via `SMAppService.mainApp` early — a tiler that dies on reboot is broken.
7. Real settings (UserDefaults/@AppStorage behind a small protocol) from the start.
8. Stable signing identity early (TCC reset per update is fatal for an AX app).
9. **One name everywhere from commit 1** (`TermTile` target/product, bundle ID `dev.ecn.apps.termtile`) — RememBar's dir/target/product drift required multi-bundle-ID cleanup machinery.
10. Port the discipline artifacts: script-invariant tests, `eventually` helper, render-to-PNG tests, JSONL diagnostics, DEBUG gallery.

## COPY / ADAPT / SKIP / IMPROVE table

| Asset | Verdict |
|---|---|
| Package.swift skeleton (Swift 6, macOS 14, exec+test, `.process("Resources")`) | **COPY** |
| Sparkle binaryTarget + rpath | **SKIP** (re-add atomically with embedding) |
| build-app script (Info.plist heredoc, LSUIElement, sips/iconutil, env-overridable) | **ADAPT** (drop SU keys/Frameworks; glob resources = IMPROVE) |
| Inside-out ad-hoc codesign, no `--deep`, verify strict | **COPY** (plan Developer ID earlier = IMPROVE) |
| `fetch-sparkle.sh` | **SKIP** now; template for vendored binaries |
| `test-packaged-app.sh` (foreign-machine launch proof) | **COPY** (+ run in CI = IMPROVE) |
| `BundleResources.swift` (Bundle.main first, Bundle.module DEBUG-only) | **COPY** |
| `test-update-e2e.sh` / `demo-update.sh` | **SKIP** until Sparkle |
| `smoke-*-diagnostics.sh` (JSONL breadcrumbs smoke) | **ADAPT** (verify tiling actions fired) |
| release.yml (VirusTotal + attestation + SHA-256 + gh release) | **ADAPT** (drop appcast; add `swift test` gate = IMPROVE) |
| SwiftLint + Semgrep + Dependabot configs | **COPY** |
| Swift Testing suite shape (TestDoubles, protocol seams, injected paths) | **COPY** pattern |
| `eventually()` anti-flake helper | **COPY** |
| Script-invariant unit tests | **COPY** |
| Offscreen render-to-PNG visual tests | **COPY** |
| DEBUG-only Gallery window | **COPY** |
| MenuBarExtra `.window` entry + delegate-adaptor + init() hooks | **ADAPT** |
| Menu-bar-window offscreen guard (pure geometry) | **COPY** (model for tiling math) |
| Permission probe + Settings deep link + blocked-status UX | **ADAPT** (AXIsProcessTrustedWithOptions + Privacy_Accessibility) |
| `RememBarPaths` identity authority | **ADAPT** (one bundle ID day 1) |
| One-click uninstall | **ADAPT** |
| JSONL diagnostics + unclean-exit breadcrumb | **ADAPT** (log AX/tiling events) |
| Dots-stripped CFBundleVersion | **IMPROVE** (collision-prone; padded/commit-count) |
| `release-notes/<version>.md` pre-tag authoring | **COPY** |
| TODO.md rationale convention; DO/GATE/SKIP tables | **COPY** |
| Launch-at-login | **IMPROVE** (add SMAppService — RememBar never did) |
| Settings persistence | **IMPROVE** (UserDefaults behind protocol) |
| `swift test` in CI | **IMPROVE** (test workflow + gated release) |
