import Foundation
import Testing

@Suite("Release readiness")
struct ReleaseReadinessTests {
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

    private static func file(_ path: String) -> String {
        let url = repoRoot().appending(path: path)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func swiftFiles(under path: String) -> [(path: String, contents: String)] {
        let root = repoRoot()
        let base = root.appending(path: path)
        let files = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        } ?? []

        return files.map { url in
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            return (rel, (try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }
    }

    @Test("0.2.0 release notes cover the post-0.1.0 user-visible changes")
    func releaseNotes020CoverUserVisibleChanges() {
        let notes = Self.file("release-notes/0.2.0.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.0.md must exist before tagging v0.2.0")

        for required in [
            "Gap",
            "shortcut",
            "drag",
            "Uninstall",
            "Accessibility",
            "Input Monitoring",
            "GitHub",
            "License",
            "update"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.0.md must mention \(required)")
        }
    }

    @Test("0.2.1 release notes explain Developer ID signing and one-time TCC reset risk")
    func releaseNotes021CoverSigningTransition() {
        let notes = Self.file("release-notes/0.2.1.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.1.md must exist before tagging v0.2.1")

        for required in [
            "Developer ID",
            "ad-hoc",
            "Accessibility",
            "Input Monitoring",
            "remove TermTile",
            "Privacy & Security > Input Monitoring",
            "Notarization"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.1.md must mention \(required)")
        }
    }

    @Test("0.2.2 release notes explain notarized and stapled distribution")
    func releaseNotes022CoverNotarizedDistribution() {
        let notes = Self.file("release-notes/0.2.2.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.2.md must exist before tagging v0.2.2")

        for required in [
            "notarized",
            "stapled",
            "Gatekeeper",
            "Developer ID",
            "Accessibility",
            "Input Monitoring"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.2.md must mention \(required)")
        }
    }

    @Test("release docs do not claim public CI can self-sign releases")
    func releaseDocsRequireDeveloperIDForPublicRelease() {
        let docs = Self.file("docs/RELEASING.md")
        #expect(docs.contains("TERMTILE_SIGN_IDENTITY"),
                "release docs must describe the release signing identity")
        #expect(docs.contains("Developer ID Application"),
                "release docs must require Developer ID Application for public releases")
        #expect(docs.contains("does not fall back"),
                "release docs must make the no-fallback public release policy explicit")
        #expect(!docs.contains("CI falls back to the stable self-signed"),
                "release docs must not describe the removed public CI self-signed fallback")
    }

    @Test("notarization runbook captures accepted evidence and release gate")
    func notarizationRunbookCapturesAcceptedEvidence() {
        let docs = Self.file("docs/NOTARIZATION.md")
        #expect(docs.contains("Accepted"),
                "Notarization runbook must record that Apple returned Accepted")
        #expect(docs.contains("a4b780fa-92be-4f61-bfc8-5aedd613ada8"),
                "Notarization runbook must record the minimal-app differential job")
        #expect(docs.contains("NotaryProbe"),
                "Notarization runbook must mention the minimal differential app")
        #expect(docs.contains("scripts/notarize-app.sh"),
                "Notarization runbook must point at the release Notary/staple script")
        #expect(docs.contains("stapler validate"),
                "Notarization runbook must require stapler validation")
        #expect(docs.contains("spctl --assess"),
                "Notarization runbook must require Gatekeeper assessment")
        #expect(docs.contains(".github/workflows/release.yml"),
                "Notarization runbook must tie the release gate to CI")
    }

    @Test("notarization runbook uses placeholder credential examples")
    func notarizationRunbookAvoidsAccountSpecificCredentialExamples() {
        let docs = Self.file("docs/NOTARIZATION.md")
        #expect(docs.contains("TERMTILE_NOTARY_KEY_PATH=/path/to/AuthKey.p8"),
                "runbook should show a local-key placeholder, not a machine-specific path")
        #expect(docs.contains("TERMTILE_NOTARY_KEY_ID=YOUR_KEY_ID"),
                "runbook should show a key-id placeholder, not an account-specific key id")
        #expect(docs.contains("TERMTILE_NOTARY_ISSUER_ID=YOUR_ISSUER_ID"),
                "runbook should show an issuer-id placeholder, not an account-specific issuer id")
        #expect(docs.contains("TERMTILE_NOTARY_FETCH_LOGS=1"),
                "runbook should include the explicit log-fetch env flag")
        #expect(!docs.contains("$HOME/Downloads/AuthKey_"),
                "runbook must not hard-code a developer machine key filename")
    }

    @Test("public docs version-qualify Developer ID notarized and stapled distribution")
    func publicDocsDescribeCurrentSigningState() {
        for path in ["README.md", "SECURITY.md"] {
            let docs = Self.file(path)
            #expect(docs.contains("Developer ID signed"),
                    "\(path) must describe the current public signing state")
            #expect(docs.contains("v0.2.2 and newer"),
                    "\(path) must version-qualify notarized/stapled claims before v0.2.2 is live")
            #expect(docs.localizedCaseInsensitiveContains("notarized"),
                    "\(path) must describe the notarized distribution state")
            #expect(docs.localizedCaseInsensitiveContains("stapled"),
                    "\(path) must describe the stapled distribution state")
            #expect(docs.contains("v0.2.1"),
                    "\(path) must preserve the v0.2.1 transitional release caveat")
            #expect(docs.localizedCaseInsensitiveContains("unstapled"),
                    "\(path) must say v0.2.1 was signed but unstapled")
            #expect(!docs.contains("not notarized yet"),
                    "\(path) must not describe the pre-0.2.2 Gatekeeper limitation")
            #expect(!docs.contains("ad-hoc signed today"),
                    "\(path) must not describe the pre-0.2.1 ad-hoc release state")
            #expect(!docs.contains("ad-hoc signed, not notarized"),
                    "\(path) must not describe the pre-0.2.1 ad-hoc release state")
        }
    }

    @Test("menu identity links do not require MacFaceKit SwiftPM resource bundles at runtime")
    func menuIdentityLinksAvoidBundleBackedBrandAssets() {
        for source in Self.swiftFiles(under: "Sources") {
            for forbidden in ["IdentityLink.github", ".github(", "Brand.github", "repoURL: AppIdentity.repoURL"] {
                #expect(!source.contents.contains(forbidden),
                        "\(source.path) must not use MacFaceKit bundle-backed identity assets")
            }
        }

        let menu = Self.file("Sources/TermTile/MenuBarContent.swift")
        #expect(menu.contains("links: identityLinks"),
                "the menu should pass package-safe identity links explicitly")
        #expect(menu.contains("IdentityLink.link(\"GitHub\""),
                "GitHub should remain present via a package-safe symbol link")
        #expect(menu.contains("IdentityLink.license(AppIdentity.licenseURL)"),
                "License should remain present in the identity card")
    }
}
