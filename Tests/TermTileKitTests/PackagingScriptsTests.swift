import Foundation
import Testing

/// #13a — the packaging scripts unit-tested AS TEXT (RememBar's "scripts unit-tested as text"
/// pattern; audit §4/§8). Each assertion pins one hard-won packaging lesson as a POSITIVE,
/// line-scoped invariant so it can't be satisfied vacuously by an empty/stub file (skeptic F1/F2).
/// The LIVE proof that the script actually produces a launchable, correctly-signed bundle is #13a's
/// PROVE (build the .app + AX/bundle-id discriminator + screencapture), not here.
@Suite("Packaging scripts — text invariants (#13a)")
struct PackagingScriptsTests {
    // Resolve the repo root via #filePath walk-up (robust vs CWD): climb until a dir has Package.swift.
    private static func repoRoot() -> URL {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate Package.swift above \(#filePath)")
    }

    private static func script(_ name: String) -> String {
        let url = repoRoot().appending(path: "scripts/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

    private static func runNotaryStatus(
        arguments: [String] = [],
        fetchLogs: Bool = false
    ) throws -> String {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appending(
            path: "termtile-notary-status-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let bin = temp.appending(path: "bin", directoryHint: .isDirectory)
        let fakeXcrun = bin.appending(path: "xcrun")
        let callsLog = temp.appending(path: "xcrun-calls.log")
        let key = temp.appending(path: "AuthKey.p8")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try "fake-key".write(to: key, atomically: true, encoding: .utf8)
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        echo "$*" >> "$TERMTILE_FAKE_XCRUN_LOG"
        test "${1:-}" = "notarytool" || { echo "unexpected xcrun command: $*" >&2; exit 98; }
        shift
        case "${1:-}" in
          history) echo '{"history":[]}' ;;
          info) echo '{"status":"In Progress"}' ;;
          log) echo '{"logFileUrl":null}' ;;
          submit) echo "submit must not be called" >&2; exit 97 ;;
          *) echo "unexpected notarytool command: $*" >&2; exit 99 ;;
        esac
        """.write(to: fakeXcrun, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeXcrun.path)
        defer { try? fm.removeItem(at: temp) }

        let process = Process()
        process.executableURL = repoRoot().appending(path: "scripts/notary-status.sh")
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(bin.path):\(env["PATH"] ?? "")"
        env["TERMTILE_FAKE_XCRUN_LOG"] = callsLog.path
        env["TERMTILE_NOTARY_KEY_PATH"] = key.path
        env["TERMTILE_NOTARY_KEY_ID"] = "TESTKEYID"
        env["TERMTILE_NOTARY_ISSUER_ID"] = "TESTISSUERID"
        env["TERMTILE_NOTARY_FETCH_LOGS"] = "0"
        if fetchLogs {
            env["TERMTILE_NOTARY_FETCH_LOGS"] = "1"
        }
        process.environment = env

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0,
                "notary-status.sh failed stdout=\(stdout) stderr=\(stderr)")
        return (try? String(contentsOf: callsLog, encoding: .utf8)) ?? ""
    }

    // 1. Inside-out codesign via the #13c identity parameter: sign lines use
    //    `--sign "$SIGN_IDENTITY"`, which resolves explicit env → local dev cert → ad-hoc FALLBACK
    //    (so CI needs no keychain), and must NOT carry `--deep` (per Sparkle/audit — `--deep` corrupts
    //    nested signatures); the VERIFY line must carry BOTH `--deep` and `--strict`. Line-scoped +
    //    positive so it can't false-fail on the verify line's legitimate `--deep`, nor pass vacuously.
    @Test("build-app.sh: sign lines use $SIGN_IDENTITY (ad-hoc fallback), no --deep; verify has --deep AND --strict")
    func codesignFlagsAreCorrect() {
        let ls = Self.lines(Self.script("build-app.sh"))
        // Inspect EVERY sign line (inside-out signs the inner Mach-O AND the bundle) — checking only
        // the first would miss a --deep smuggled onto a later sign line (caught by the invert-check).
        let signLines = ls.filter { l in
            l.contains("codesign") && l.contains("--sign \"$SIGN_IDENTITY\"")
        }
        #expect(!signLines.isEmpty, "no codesign --sign \"$SIGN_IDENTITY\" line found")
        #expect(signLines.allSatisfy { !$0.contains("--deep") }, "no sign line may contain --deep")
        #expect(signLines.allSatisfy { $0.contains("--options runtime") },
                "every sign line must enable hardened runtime for notarization")
        // Resolution: explicit TERMTILE_SIGN_IDENTITY wins; else auto-use the local dev cert IF present;
        // else fall back to ad-hoc so CI (no env, no keychain cert) needs no signing setup (#13c).
        let script = Self.script("build-app.sh")
        #expect(script.contains("sign_code()"), "build-app.sh must keep signing flags centralized")
        #expect(script.contains("TERMTILE_SIGN_IDENTITY"), "explicit sign-identity override must exist")
        #expect(script.contains("SIGN_IDENTITY=\"-\""),
                "SIGN_IDENTITY must fall back to ad-hoc (\"-\") so CI needs no keychain")

        let verifyLine = ls.first { $0.contains("codesign") && $0.contains("--verify") }
        #expect(verifyLine != nil, "no codesign --verify line found")
        #expect(verifyLine?.contains("--deep") == true, "verify line must contain --deep")
        #expect(verifyLine?.contains("--strict") == true, "verify line must contain --strict")
    }

    @Test("build-app.sh: app signature disables library validation only for local Sparkle builds")
    func localAppSignatureAllowsEmbeddedSparkleWithoutWeakeningDeveloperIDReleases() {
        let script = Self.script("build-app.sh")
        #expect(script.contains("com.apple.security.cs.disable-library-validation"),
                "local self-signed hardened-runtime builds must be allowed to load embedded Sparkle")
        #expect(script.contains("TERMTILE_DISABLE_LIBRARY_VALIDATION"),
                "library-validation policy must have an explicit override for exceptional builds")
        #expect(script.contains("\"Developer ID Application:\"*)") && script.contains("DISABLE_LIBRARY_VALIDATION=0"),
                "Developer ID releases must not disable library validation by default")
        #expect(script.contains("--entitlements \"$ENTITLEMENTS\""),
                "the app signing path must apply the entitlement file")
        #expect(script.contains("sign_app_code()"),
                "app signing with entitlements should stay centralized")
    }

    // 2. Monotonic CFBundleVersion from commit count; never dots-stripped (audit §8.5 collision bug:
    //    `0.10.1 → 0101`). Positive presence of the real source + absence of every dots-strip idiom.
    @Test("build-app.sh: CFBundleVersion uses git rev-list --count, never dots-stripped")
    func buildNumberIsMonotonic() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("git rev-list --count"), "build number must come from git rev-list --count")
        #expect(s.contains("TERMTILE_BUILD_NUMBER"),
                "local downgrade verification builds need an explicit CFBundleVersion override")
        #expect(!s.contains("tr -d '.'"), "must not dots-strip the version (tr -d '.')")
        #expect(!s.contains("//./"), "must not dots-strip the version (bash //./ substitution)")
        #expect(!s.contains("s/\\.//g"), "must not dots-strip the version (sed s/./g)")
    }

    @Test("build-app.sh: build-number override is explicit and validated")
    func buildNumberOverrideIsExplicitAndValidated() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("TERMTILE_BUILD_NUMBER"),
                "the override should have an app-specific env name, not a generic BUILD_NUMBER")
        #expect(s.contains("[[ \"$TERMTILE_BUILD_NUMBER\" =~ ^[1-9][0-9]*$ ]]"),
                "the override should reject non-positive or non-numeric bundle versions")
        #expect(s.contains("GITHUB_ACTIONS"),
                "release CI must reject local-only build-number overrides")
        #expect(s.contains("git rev-list --count HEAD"),
                "the default release path must remain the monotonic git commit count")
    }

    // 3. Menu-bar-only bundle + a lint gate on the generated plist.
    @Test("build-app.sh: sets LSUIElement and lints the Info.plist")
    func plistIsMenuBarAndLinted() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("LSUIElement"), "Info.plist must set LSUIElement (menu-bar only)")
        #expect(s.contains("plutil -lint"), "the generated Info.plist must be plutil -lint'ed")
    }

    @Test("build-app.sh: disables Sparkle automatic-check prompting for passive startup probes")
    func plistDisablesSparkleAutomaticCheckPrompting() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("SUEnableAutomaticChecks"),
                "the generated Info.plist must explicitly choose automatic update-check prompting behavior")
        #expect(s.contains("<key>SUEnableAutomaticChecks</key>") && s.contains("<false/>"),
                "startup availability probes should not reintroduce Sparkle's automatic-check permission prompt")
    }

    // 4. Locate the built binary via --show-bin-path (RememBar crown-jewel), never a hardcoded
    //    .build/{debug,release} path (which rots across configs/toolchains).
    @Test("build-app.sh: locates binary via --show-bin-path, no hardcoded .build path")
    func binaryLocatedRobustly() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("--show-bin-path"), "must locate the binary via swift build --show-bin-path")
        #expect(!s.contains(".build/debug"), "must not hardcode .build/debug")
        #expect(!s.contains(".build/release"), "must not hardcode .build/release")
    }

    // 5. A signed macOS .app cannot carry arbitrary unsealed content at the bundle root. If a package
    //    dependency needs Bundle.module resources, the app must avoid that runtime path or move the
    //    invariant into the dependency; build-app.sh must not copy Package_Target.bundle to TermTile.app/.
    @Test("build-app.sh: does not copy SwiftPM resource bundles to the app root")
    func buildAvoidsAppRootSwiftPMResourceBundles() {
        let s = Self.script("build-app.sh")
        #expect(!s.contains("\"$APP/$RESOURCE_NAME\""),
                "app-root SwiftPM bundles produce unsealed contents during codesign")
    }

    // 6. The launch smoke really launches + verifies (positive kill -0 + codesign --verify) and never
    //    globally kills a process (RememBar safety invariant — no pkill/killall).
    @Test("test-packaged-app.sh: launches (kill -0) + verifies signature, never pkill/killall")
    func smokeLaunchesAndIsSafe() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("kill -0"), "smoke must poll liveness with kill -0")
        #expect(s.contains("wait \"$PID\""),
                "smoke cleanup must wait after killing the launched app to avoid noisy shell output")
        #expect(s.contains("codesign") && s.contains("--verify"), "smoke must codesign --verify the bundle")
        // Line-scoped to CODE (skip comment lines): a "never pkill" comment is fine; INVOKING it isn't.
        let codeLines = Self.lines(s).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        #expect(!codeLines.contains { $0.contains("pkill") }, "smoke must never invoke pkill")
        #expect(!codeLines.contains { $0.contains("killall") }, "smoke must never invoke killall")
    }

    @Test("install-app.sh waits for the old app and retries LaunchServices relaunch")
    func installWaitsForOldAppAndRetriesRelaunch() {
        let s = Self.script("install-app.sh")
        #expect(s.contains("wait_for_app_exit"),
                "install should not race relaunch against the previous app's shutdown")
        #expect(s.contains("rm -rf \"$HOME/Applications/$APP_NAME.app\""),
                "install should remove the old user-Applications bundle, not just an extensionless path")
        #expect(s.contains("rm -rf \"$HOME/Applications/$APP_NAME\""),
                "install should keep cleaning the legacy extensionless migration path")
        #expect(s.contains("open \"$INSTALLED_APP\""),
                "install should try the normal LaunchServices relaunch path first")
        #expect(s.contains("open -n \"$INSTALLED_APP\""),
                "install should retry with a fresh instance when LaunchServices returns a transient error")
    }

    @Test("test-packaged-app.sh: can require stable non-ad-hoc code signing")
    func smokeCanRejectAdHocSigning() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("REQUIRE_STABLE_CODESIGN"),
                "release smoke must be able to require stable code signing")
        #expect(s.contains("Signature=adhoc"),
                "stable-signing mode must explicitly reject ad-hoc signatures")
        #expect(s.contains(#"cdhash H\""#),
                "stable-signing mode must reject cdhash-only designated requirements")
        #expect(s.contains("Authority="),
                "stable-signing mode must require a certificate authority in the signature")
        #expect(s.contains("REQUIRE_DEVELOPER_ID_CODESIGN"),
                "release smoke must be able to require Developer ID signing")
        #expect(s.contains("Authority=Developer ID Application:"),
                "Developer ID mode must require a Developer ID Application authority")
        #expect(s.contains("REQUIRE_CODESIGN_TEAM_ID"),
                "Developer ID mode must pin the expected Apple Team ID")
        #expect(s.contains("TeamIdentifier=$REQUIRE_CODESIGN_TEAM_ID"),
                "Developer ID mode must verify the signed artifact's TeamIdentifier")
        #expect(s.contains("certificate leaf[subject.OU] = $REQUIRE_CODESIGN_TEAM_ID"),
                "Developer ID mode must verify the designated requirement binds the expected team")
        #expect(s.contains("codesign -d --entitlements :- \"$APP\""),
                "Developer ID mode must inspect the shipped app entitlements")
        #expect(s.contains("com.apple.security.cs.disable-library-validation"),
                "Developer ID mode must reject the local Sparkle library-validation entitlement")
    }

    // 7. The smoke must not let local `.build` resource bundles mask a missing packaged bundle.
    @Test("test-packaged-app.sh: hides local SwiftPM resource bundles before launch")
    func smokeHidesLocalSwiftPMResourceBundles() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("BUILD_BUNDLE_BACKUP"),
                "smoke must move local .build resource bundles aside before launching the package")
        #expect(s.contains("-name '*_*.bundle'"),
                "smoke must locate SwiftPM resource bundles generically")
        #expect(s.contains("TERMTILE_SELFTEST=1 TERMTILE_GALLERY=1"),
                "smoke must render the real panel with an isolated selftest settings suite")
        #expect(s.contains("GALLERY_LOG"),
                "smoke must capture gallery output instead of discarding it")
        #expect(s.contains("grep -q \"GALLERY shown\" \"$GALLERY_LOG\""),
                "smoke must prove the real panel rendered, not only that the process stayed alive")
    }

    @Test("test-packaged-app.sh: validates passive update probe startup")
    func smokeValidatesPassiveUpdateProbeStartup() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("SUEnableAutomaticChecks"),
                "smoke must assert Sparkle automatic checks remain disabled in the bundle")
        #expect(s.contains("TERMTILE_UPDATE_PROBE_SMOKE=1"),
                "smoke must launch the packaged app through the passive update probe path")
        #expect(s.contains("UPDATE_PROBE_SMOKE armed"),
                "smoke must prove the packaged app actually armed the passive probe")
        #expect(s.contains("UPDATE_PROBE_SMOKE finished"),
                "smoke must prove the passive information-check delegate path finished")
        #expect(s.contains("CFFIXED_USER_HOME=\"$SMOKE_HOME\""),
                "smoke must isolate CFPreferences while launching packaged validation hooks")
    }

    // 8. The smoke mutates generated `.build` bundles to make the launch proof honest. Cleanup must
    //    restore every bundle best-effort and preserve the original script status, otherwise a failed
    //    restore can leave the developer's build tree in a misleading state.
    @Test("test-packaged-app.sh: restores hidden SwiftPM bundles best-effort")
    func smokeRestoreIsBestEffortAndPreservesStatus() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("local status=$?"), "cleanup must capture the original exit status")
        #expect(s.contains("trap - EXIT"), "cleanup must not recursively trigger itself")
        #expect(s.contains("restore_status=0"), "restore must accumulate failures instead of exiting early")
        #expect(s.contains("restore_status=1"), "restore must mark failed mkdir/mv operations")
        #expect(s.contains("exit \"$status\""), "cleanup must exit with the preserved or upgraded status")
    }

    // 9. The Bundle.module guard must understand real Swift conditional blocks. A line-only
    //    `grep -v '#if DEBUG'` false-fails on the intended helper, where `Bundle.module` is on the
    //    line after the DEBUG guard.
    @Test("test-packaged-app.sh: Bundle.module regression guard is DEBUG-block aware")
    func bundleModuleGuardIsDebugBlockAware() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("debugDepth"), "Bundle.module guard must track DEBUG preprocessor depth")
        #expect(!s.contains("grep -v '#if DEBUG'"),
                "Bundle.module guard must not rely on same-line grep filtering")
    }

    @Test("notarize-app.sh: submits, staples, validates, and Gatekeeper-assesses the app")
    func notarizeScriptIsRealWorkflow() {
        let s = Self.script("notarize-app.sh")
        #expect(s.contains("scripts/lib/notary-auth.sh"),
                "notarize-app.sh must source the shared Notary auth helper")
        #expect(s.contains("termtile_notary_prepare_auth"),
                "notarize-app.sh must initialize credentials through the shared helper")
        #expect(s.contains(#""${TERMTILE_NOTARY_ARGS[@]}""#),
                "notarize-app.sh must pass Notary credentials through the shared args array")
        #expect(s.contains("ditto -c -k --keepParent"),
                "notarize-app.sh must submit a parent-preserving zip archive")
        #expect(s.contains("notarytool submit") && s.contains("--wait"),
                "notarize-app.sh must wait for Apple notarization to complete")
        #expect(s.contains(#""Accepted""#),
                "notarize-app.sh must fail unless Apple returns Accepted")
        #expect(s.contains("PIPESTATUS"),
                "notarize-app.sh must preserve notarytool's exit status through tee")
        #expect(s.contains("notarytool info"),
                "notarize-app.sh must report the job status when a wait times out")
        #expect(s.contains("notarytool log"),
                "notarize-app.sh must fetch Apple's log on failure")
        #expect(s.contains("stapler staple"),
                "notarize-app.sh must staple the notarization ticket to the app")
        #expect(s.contains("stapler validate"),
                "notarize-app.sh must validate the stapled ticket")
        #expect(s.contains("spctl --assess"),
                "notarize-app.sh must prove Gatekeeper accepts the final app")
    }

    @Test("notary auth helper: one credential authority for Notary scripts")
    func notaryAuthHelperIsSharedCredentialAuthority() {
        let s = Self.script("lib/notary-auth.sh")
        #expect(s.contains("termtile_notary_prepare_auth"),
                "Notary auth helper must expose credential preparation")
        #expect(s.contains("TERMTILE_NOTARY_KEY_P8_BASE64"),
                "Notary auth helper must materialize the CI .p8 key from a secret")
        #expect(s.contains("TERMTILE_NOTARY_KEY_PATH"),
                "Notary auth helper must support a local key path for pre-release validation")
        #expect(s.contains("TERMTILE_NOTARY_ARGS=("),
                "Notary auth helper must expose one shared notarytool args array")
        #expect(s.contains("chmod 600"),
                "Notary auth helper must lock down any materialized .p8 key file")
    }

    @Test("notary-status.sh: polls existing submissions without uploading")
    func notaryStatusScriptDoesNotSubmit() {
        let s = Self.script("notary-status.sh")
        #expect(s.contains("scripts/lib/notary-auth.sh"),
                "notary-status.sh must source the shared Notary auth helper")
        #expect(s.contains("notarytool history"),
                "notary-status.sh with no IDs must read submission history")
        #expect(s.contains("notarytool info"),
                "notary-status.sh with IDs must read existing submission status")
        #expect(s.contains("TERMTILE_NOTARY_FETCH_LOGS"),
                "notary-status.sh must make log fetching explicit, not noisy by default")
        #expect(!s.contains("notarytool submit"),
                "notary-status.sh must not create new Notary submissions")
    }

    @Test("notary-status.sh behavior: reads history/info/log only, never submit")
    func notaryStatusBehaviorIsReadOnly() throws {
        let historyCalls = try Self.runNotaryStatus()
        #expect(historyCalls.contains("notarytool history"),
                "no-ID status check must read Notary history")
        #expect(!historyCalls.contains("notarytool submit"),
                "no-ID status check must not submit")

        let infoCalls = try Self.runNotaryStatus(arguments: ["job-one", "job-two"])
        #expect(infoCalls.contains("notarytool info job-one"),
                "ID status check must inspect the first requested job")
        #expect(infoCalls.contains("notarytool info job-two"),
                "ID status check must inspect every requested job")
        #expect(!infoCalls.contains("notarytool log"),
                "ID status check must not fetch logs unless explicitly requested")
        #expect(!infoCalls.contains("notarytool submit"),
                "ID status check must not submit")

        let logCalls = try Self.runNotaryStatus(arguments: ["job-one"], fetchLogs: true)
        #expect(logCalls.contains("notarytool info job-one"),
                "log mode must still inspect the requested job")
        #expect(logCalls.contains("notarytool log job-one"),
                "log mode must fetch logs for the requested job")
        #expect(!logCalls.contains("notarytool submit"),
                "log mode must not submit")
    }

    // 11. Scripts exist and are executable (a text-present stub that isn't chmod +x never runs).
    @Test("packaging scripts exist and are executable")
    func scriptsAreExecutable() {
        let fm = FileManager.default
        for name in ["build-app.sh", "test-packaged-app.sh", "notarize-app.sh", "notary-status.sh"] {
            let path = Self.repoRoot().appending(path: "scripts/\(name)").path
            #expect(fm.fileExists(atPath: path), "\(name) must exist")
            #expect(fm.isExecutableFile(atPath: path), "\(name) must be executable (chmod +x)")
        }
    }
}
