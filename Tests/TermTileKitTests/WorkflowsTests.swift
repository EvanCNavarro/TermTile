import Foundation
import Testing

/// #13b - the CI workflow YAMLs unit-tested AS TEXT (same pattern as PackagingScriptsTests;
/// RememBar's "scripts unit-tested as text", audit sec.4/8). Each assertion pins one audit CI
/// lesson as a POSITIVE, line-scoped invariant so it cannot pass vacuously on an empty/stub file
/// (skeptic F1/F2). These prove the workflows CONTAIN the mandated wiring; the SUBSTANCE (swift
/// test + swiftlint actually green) is proven by RUNNING those commands locally, and the LIVE
/// GitHub-runner execution is the external #20 deferral. Red-first: release/semgrep do not exist
/// yet and check.yml is still the npm placeholder.
@Suite("CI workflows - text invariants (#13b)")
struct WorkflowsTests {
    // Repo root via #filePath walk-up (robust vs CWD): climb until a dir has Package.swift.
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

    private static func workflow(_ name: String) -> String {
        let url = repoRoot().appending(path: ".github/workflows/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func file(_ path: String) -> String {
        let url = repoRoot().appending(path: path)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

    // 1. check.yml is the SWIFT gate (audit sec.8.1 biggest gap): runs `swift test` on a macOS runner
    //    (swift test needs AppKit/ApplicationServices), NOT ubuntu, NOT the npm placeholder.
    @Test("check.yml: runs swift test on macOS, not npm/ubuntu")
    func checkRunsSwiftTestOnMacOS() {
        let s = Self.workflow("check.yml")
        #expect(s.contains("swift test"), "check.yml must run swift test (the CI test gate)")
        #expect(s.contains("runs-on: macos"), "check.yml must run on a macOS runner (swift test needs AppKit)")
        #expect(!s.contains("runs-on: ubuntu"), "check.yml must not run on ubuntu (no macOS frameworks)")
        #expect(!s.contains("npm run check"), "check.yml must not invoke the npm placeholder")
    }

    // 2. check.yml also lints, and preserves the load-bearing policy elements (REPOSITORY_POLICY.md:5,16):
    //    the required-status-check name `Check` + least-privilege `permissions: contents: read`.
    @Test("check.yml: runs swiftlint; keeps name Check + least-privilege permissions")
    func checkLintsAndKeepsPolicy() {
        let s = Self.workflow("check.yml")
        #expect(s.contains("swiftlint"), "check.yml must run swiftlint (the lint gate)")
        #expect(s.contains("name: Check"), "check.yml must keep name: Check (required status check)")
        #expect(s.contains("contents: read"), "check.yml must keep least-privilege permissions: contents: read")
    }

    // 3. release.yml is GATED on swift test (audit sec.8 #83/#84) and CALLS the packaging script
    //    (audit #85 - do not duplicate the build), on a `v*` tag, with build provenance attested.
    @Test("release.yml: swift-test gated, calls build-app.sh, tag v* trigger, attests provenance")
    func releaseIsGatedAndCallsScript() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("swift test"), "release.yml must be gated on swift test")
        #expect(s.contains("scripts/build-app.sh"), "release.yml must call scripts/build-app.sh, not duplicate the build")
        #expect(s.contains("attest-build-provenance@v4"), "release.yml must attest build provenance (pinned @v4 per audit)")
        // tag trigger: a `tags:` block listing a `v*` pattern.
        let ls = Self.lines(s)
        #expect(ls.contains { $0.contains("tags:") }, "release.yml must trigger on tags")
        #expect(ls.contains { $0.contains("'v*'") || $0.contains("\"v*\"") || $0.contains("- v*") },
                "release.yml must trigger on the v* tag pattern")
    }

    @Test("release.yml: derives marketing version from the tag, not build-app.sh's local default")
    func releaseDerivesMarketingVersionFromTag() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("SHORT_VERSION=\"${GITHUB_REF_NAME#v}\" scripts/build-app.sh"),
                "release.yml must pass the tag-derived marketing version into build-app.sh")
        #expect(s.contains("GITHUB_REF_NAME#v"),
                "release.yml must strip the leading v from the SemVer tag")
    }

    @Test("release.yml: runs strict SwiftLint before publishing")
    func releaseRunsStrictSwiftLint() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("brew install swiftlint"), "release.yml must install SwiftLint on the macOS runner")
        #expect(s.contains("swiftlint --strict"), "release.yml must run the same strict lint gate before publishing")
    }

    @Test("release.yml: imports a stable signing identity before building public artifacts")
    func releaseImportsStableSigningIdentity() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("TERMTILE_RELEASE_SIGNING_CERT_P12_BASE64"),
                "release.yml must import a stable signing certificate from GitHub secrets")
        #expect(s.contains("TERMTILE_RELEASE_SIGNING_CERT_PASSWORD"),
                "release.yml must unlock the signing certificate with a GitHub secret")
        #expect(s.contains("DeveloperIDG2CA.cer"),
                "release.yml must import Apple's Developer ID G2 intermediate into the CI keychain")
        #expect(s.contains("security add-certificates"),
                "release.yml must add the Developer ID intermediate before resolving signing identities")
        #expect(s.contains("security import"),
                "release.yml must import the signing identity into a temporary keychain")
        #expect(s.contains("TERMTILE_SIGN_IDENTITY: ${{ vars.TERMTILE_SIGN_IDENTITY }}"),
                "release.yml must take the release signing identity from the repo variable")
        #expect(s.contains("TERMTILE_SIGN_IDENTITY repo variable is not set"),
                "release.yml must fail fast when the release signing identity variable is missing")
        #expect(s.contains("Developer\\ ID\\ Application:*"),
                "release.yml must require a Developer ID Application identity for public releases")
        #expect(!s.contains("vars.TERMTILE_SIGN_IDENTITY || 'TermTile Dev Signing'"),
                "public release workflow must not fall back to self-signed dev identity")
    }

    @Test("release.yml: release smoke rejects ad-hoc signatures before publishing")
    func releaseRejectsAdHocArtifacts() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("REQUIRE_STABLE_CODESIGN: \"1\""),
                "release.yml must require stable code signing for release smoke")
        #expect(s.contains("REQUIRE_DEVELOPER_ID_CODESIGN: \"1\""),
                "release.yml must require Developer ID signing for release smoke")
        #expect(s.contains("REQUIRE_CODESIGN_TEAM_ID: XG9SBNWNXT"),
                "release.yml must pin the expected Developer ID Team ID")
        #expect(s.contains("scripts/test-packaged-app.sh \"${{ steps.build.outputs.app_path }}\""),
                "release.yml must run the packaged smoke with the stable-signing guard enabled")
    }

    @Test("release.yml: runs packaged-app smoke before publishing")
    func releaseRunsPackagedAppSmokeBeforePublishing() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("scripts/test-packaged-app.sh \"${{ steps.build.outputs.app_path }}\""),
                "release.yml must run the native packaged-app smoke against the built artifact")

        let build = s.range(of: "- name: Build .app")?.lowerBound
        let smoke = s.range(of: "scripts/test-packaged-app.sh")?.lowerBound
        let package = s.range(of: "- name: Package + checksum")?.lowerBound
        #expect(build != nil, "release.yml must have a Build .app step")
        #expect(smoke != nil, "release.yml must have a packaged-app smoke step")
        #expect(package != nil, "release.yml must have a Package + checksum step")
        if let build, let smoke, let package {
            #expect(build < smoke && smoke < package,
                    "packaged-app smoke must run after build and before zip/appcast publishing")
        }
    }

    @Test("release.yml: notarizes and staples the app before packaging")
    func releaseNotarizesAndStaplesBeforePackaging() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("- name: Notarize and staple .app"),
                "release.yml must have an explicit Notarize and staple .app step")
        #expect(s.contains("scripts/notarize-app.sh \"${{ steps.build.outputs.app_path }}\""),
                "release.yml must reuse scripts/notarize-app.sh for the Notary/staple workflow")
        #expect(s.contains("TERMTILE_NOTARY_KEY_P8_BASE64: ${{ secrets.TERMTILE_NOTARY_KEY_P8_BASE64 }}"),
                "release.yml must read the Notary p8 key from GitHub secrets")
        #expect(s.contains("TERMTILE_NOTARY_KEY_ID: ${{ secrets.TERMTILE_NOTARY_KEY_ID }}"),
                "release.yml must read the Notary key id from GitHub secrets")
        #expect(s.contains("TERMTILE_NOTARY_ISSUER_ID: ${{ secrets.TERMTILE_NOTARY_ISSUER_ID }}"),
                "release.yml must read the Notary issuer id from GitHub secrets")

        let smoke = s.range(of: "- name: Smoke packaged app")?.lowerBound
        let notarize = s.range(of: "- name: Notarize and staple .app")?.lowerBound
        let package = s.range(of: "- name: Package + checksum")?.lowerBound
        #expect(smoke != nil, "release.yml must keep the pre-notarization packaged-app smoke step")
        #expect(notarize != nil, "release.yml must have a notarization step")
        #expect(package != nil, "release.yml must have a Package + checksum step")
        if let smoke, let notarize, let package {
            #expect(smoke < notarize && notarize < package,
                    "release CI must smoke the signed app, notarize/staple it, then zip the stapled app")
        }
    }

    @Test("release.yml: appcast uses embedded release notes and is published")
    func releasePublishesSignedAppcastWithNotes() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}"),
                "release.yml must sign the appcast with the Sparkle private key from GitHub secrets")
        #expect(s.contains("--embed-release-notes"),
                "release.yml must embed release-notes/<version>.md into Sparkle's appcast item")
        #expect(s.contains("dist/appcast.xml"),
                "release.yml must publish the generated appcast.xml as a release asset")
        #expect(s.contains("--notes-file"),
                "release.yml must use the same release-notes/<version>.md as the GitHub release body")
    }

    // 4. Secrets are referenced ONLY via the GitHub secrets context - never inlined. Positive presence
    //    of the VirusTotal secret reference; negative absence of an inlined long token literal.
    @Test("release.yml: VirusTotal secret via secrets context, no inlined token")
    func releaseSecretsAreNotInlined() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("secrets.VIRUSTOTAL_API_KEY"),
                "release.yml must read the VirusTotal key from the secrets context")
        #expect(s.contains("secrets.SPARKLE_ED_PRIVATE_KEY"),
                "release.yml must read the Sparkle private key from the secrets context")
        #expect(s.contains("secrets.TERMTILE_RELEASE_SIGNING_CERT_P12_BASE64"),
                "release.yml must read the signing certificate from the secrets context")
        #expect(s.contains("secrets.TERMTILE_RELEASE_SIGNING_CERT_PASSWORD"),
                "release.yml must read the signing certificate password from the secrets context")
        #expect(s.contains("secrets.TERMTILE_NOTARY_KEY_P8_BASE64"),
                "release.yml must read the Notary p8 key from the secrets context")
        #expect(s.contains("secrets.TERMTILE_NOTARY_KEY_ID"),
                "release.yml must read the Notary key id from the secrets context")
        #expect(s.contains("secrets.TERMTILE_NOTARY_ISSUER_ID"),
                "release.yml must read the Notary issuer id from the secrets context")
        // A secret/token assignment must resolve through a `${{ }}` context (secrets.* or github.*),
        // never a bare literal (e.g. `VIRUSTOTAL_API_KEY: abc123...`). Context refs are safe.
        let codeLines = Self.lines(s).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let inlinedSecret = codeLines.contains { l in
            (l.contains("API_KEY:") || l.contains("PRIVATE_KEY:") || l.contains("TOKEN:")
             || l.contains("CERT_P12_BASE64:") || l.contains("CERT_PASSWORD:")
             || l.contains("NOTARY_KEY_P8_BASE64:") || l.contains("NOTARY_KEY_ID:")
             || l.contains("NOTARY_ISSUER_ID:"))
                && !l.contains("${{")
        }
        #expect(!inlinedSecret, "no workflow line may assign a secret to an inlined literal")
    }

    // 5. semgrep.yml uses BOTH mandated rule packs (audit line 35): p/security-audit + p/secrets.
    @Test("semgrep.yml: uses p/security-audit and p/secrets")
    func semgrepUsesBothPacks() {
        let s = Self.workflow("semgrep.yml")
        #expect(s.contains("p/security-audit"), "semgrep.yml must run the p/security-audit pack")
        #expect(s.contains("p/secrets"), "semgrep.yml must run the p/secrets pack")
    }

    // 6. The lint gate keeps force_cast a STRICT rule (scoped inline at the AX sites, not disabled).
    @Test(".swiftlint.yml: keeps force_cast strict (not globally disabled)")
    func swiftlintConfigIsHonest() {
        let cfg = Self.file(".swiftlint.yml")
        // force_cast must NOT be globally disabled (it is scoped inline at the AX sites instead).
        #expect(!cfg.contains("- force_cast"), ".swiftlint.yml must not globally disable force_cast")
    }
}
