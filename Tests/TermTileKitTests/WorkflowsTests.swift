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

    // 4. Secrets are referenced ONLY via the GitHub secrets context - never inlined. Positive presence
    //    of the VirusTotal secret reference; negative absence of an inlined long token literal.
    @Test("release.yml: VirusTotal secret via secrets context, no inlined token")
    func releaseSecretsAreNotInlined() {
        let s = Self.workflow("release.yml")
        #expect(s.contains("secrets.VIRUSTOTAL_API_KEY"),
                "release.yml must read the VirusTotal key from the secrets context")
        // A secret/token assignment must resolve through a `${{ }}` context (secrets.* or github.*),
        // never a bare literal (e.g. `VIRUSTOTAL_API_KEY: abc123...`). Context refs are safe.
        let codeLines = Self.lines(s).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let inlinedSecret = codeLines.contains { l in
            (l.contains("API_KEY:") || l.contains("TOKEN:")) && !l.contains("${{")
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

    // 6. The lint gate has a config, and it is honest: it excludes the throwaway AXProbe spike and
    //    keeps force_cast a STRICT rule (scoped inline at the 2 AX sites, not globally disabled).
    @Test(".swiftlint.yml: excludes throwaway AXProbe, keeps force_cast strict (not disabled)")
    func swiftlintConfigIsHonest() {
        let cfg = Self.file(".swiftlint.yml")
        #expect(cfg.contains("Sources/AXProbe"), ".swiftlint.yml must exclude the throwaway AXProbe spike")
        // force_cast must NOT be globally disabled (it is scoped inline at the AX sites instead).
        #expect(!cfg.contains("- force_cast"), ".swiftlint.yml must not globally disable force_cast")
    }
}
