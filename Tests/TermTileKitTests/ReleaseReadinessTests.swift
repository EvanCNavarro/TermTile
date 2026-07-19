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

    private static func data(_ path: String) -> Data {
        let url = repoRoot().appending(path: path)
        return (try? Data(contentsOf: url)) ?? Data()
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func resolvedVersion(for identity: String) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: Self.data("Package.resolved")) as? [String: Any],
              let pins = root["pins"] as? [[String: Any]] else { return nil }
        for pin in pins where pin["identity"] as? String == identity {
            return (pin["state"] as? [String: Any])?["version"] as? String
        }
        return nil
    }

    private static func semver(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap(Int.init)
        return numbers.count == 3 ? numbers : nil
    }

    private static func semver(_ version: String, isAtLeast floor: String, below ceiling: String) -> Bool {
        guard let version = semver(version),
              let floor = semver(floor),
              let ceiling = semver(ceiling) else { return false }
        return version.lexicographicallyPrecedes(floor) == false && version.lexicographicallyPrecedes(ceiling)
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

    @Test("0.2.3 release notes explain stale permission repair")
    func releaseNotes023CoverPermissionRepair() {
        let notes = Self.file("release-notes/0.2.3.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.3.md must exist before tagging v0.2.3")

        for required in [
            "Repair Accessibility",
            "Repair Input Monitoring",
            "stale",
            "older",
            "ad-hoc",
            "TCC"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.3.md must mention \(required)")
        }
    }

    @Test("0.2.4 release notes explain uninstall privacy cleanup")
    func releaseNotes024CoverUninstallPrivacyCleanup() {
        let notes = Self.file("release-notes/0.2.4.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.4.md must exist before tagging v0.2.4")

        for required in [
            "Uninstall",
            "TCC",
            "Repair Accessibility",
            "Repair Input Monitoring",
            "Accessibility",
            "Input Monitoring",
            "notarized",
            "stapled"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.4.md must mention \(required)")
        }
    }

    @Test("0.2.5 release notes explain optional app focus on Rearrange")
    func releaseNotes025CoverBringAppForward() {
        let notes = Self.file("release-notes/0.2.5.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.5.md must exist before tagging v0.2.5")

        for required in [
            "Bring app forward",
            "Rearrange",
            "target app",
            "default off",
            "macOS",
            "focus"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.5.md must mention \(required)")
        }
    }

    @Test("0.2.6 release notes explain update availability indicators")
    func releaseNotes026CoverUpdateAvailabilityIndicators() {
        let notes = Self.file("release-notes/0.2.6.md")
        #expect(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "release-notes/0.2.6.md must exist before tagging v0.2.6")

        for required in [
            "update available",
            "menu bar",
            "ellipsis",
            "Check for Updates",
            "passive",
            "Sparkle",
            "drag-reorder",
            "text selection",
            "screenshot"
        ] {
            #expect(notes.localizedCaseInsensitiveContains(required),
                    "release-notes/0.2.6.md must mention \(required)")
        }
    }

    @Test("0.2.6 local verification records drag QOL evidence")
    func releaseVerification026RecordsDragQOLEvidence() {
        let docs = Self.file("docs/verification/release-v0.2.6-local.md")
        #expect(!docs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "docs/verification/release-v0.2.6-local.md must record local v0.2.6 candidate evidence")

        for required in [
            "iTerm content-drag",
            "screenshot-region drag",
            "before=0,38,1728,1030",
            "after=0,38,1728,1030",
            "PASS",
            "local candidate only"
        ] {
            #expect(docs.localizedCaseInsensitiveContains(required),
                    "docs/verification/release-v0.2.6-local.md must mention \(required)")
        }
    }

    @Test("0.2.6 public verification records shipped artifacts")
    func releaseVerification026RecordsPublishedArtifacts() {
        let docs = Self.file("docs/verification/release-v0.2.6.md")
        #expect(!docs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "docs/verification/release-v0.2.6.md must record published v0.2.6 evidence")

        for required in [
            "v0.2.6",
            "a9ec44a373a264420d19d86aeda158c5b5f9b131",
            "Build version: `138`",
            "gh attestation verify",
            "appcast.xml",
            "EdDSA",
            "xcrun stapler validate",
            "spctl --assess",
            "Notarized Developer ID",
            "User-Facing Downgrade Indicator Smoke",
            "real `v0.2.5` release cannot show the new indicator",
            "CFBundleVersion`: `137`",
            "UPDATE_PROBE_SMOKE available"
        ] {
            #expect(docs.localizedCaseInsensitiveContains(required),
                    "docs/verification/release-v0.2.6.md must mention \(required)")
        }
    }

    @Test("Decision 0003 documents the full plan and progress-reporting contract")
    func decision003DocumentsFullPlanAndProgressContract() {
        let docs = Self.file("docs/decisions/0003-update-availability-indicators.md")

        for required in [
            "Current progress: Phase 11 complete",
            "### Phase 11: Public release and post-release documentation",
            "/order",
            "/chug-02-continue",
            "At the end of every implementation turn, report:",
            "Current phase and substep.",
            "Approximate total progress percentage.",
            "Validation run in that turn.",
            "Whether local nits, polish, flakes, or cleanup remain.",
            "Next steps, including whether more work is required.",
            "superpowers:code-reviewer"
        ] {
            #expect(docs.localizedCaseInsensitiveContains(required),
                    "docs/decisions/0003-update-availability-indicators.md must mention \(required)")
        }
    }

    @Test("handoff points release operators at the latest public verification")
    func handoffRecordsLatestPublicReleaseVerification() {
        let docs = Self.file("HANDOFF.md")

        for required in [
            "Latest published release | **v0.2.6**",
            "latest completed for `v0.2.6`",
            "TermTile-v0.2.6.zip --repo EvanCNavarro/TermTile",
            "docs/verification/release-v0.2.6.md"
        ] {
            #expect(docs.localizedCaseInsensitiveContains(required),
                    "HANDOFF.md must mention \(required)")
        }

        #expect(!docs.localizedCaseInsensitiveContains("Post-release artifact verification** - completed for `v0.2.5`"),
                "HANDOFF.md must not leave the post-release verification item pinned to v0.2.5")
    }

    @Test("handoff records the current MacFaceKit dependency line")
    func handoffRecordsCurrentMacFaceKitDependencyLine() {
        let docs = Self.file("HANDOFF.md")
        #expect(docs.contains("MacFaceKit `.upToNextMinor(from: \"0.4.2\")`"),
                "HANDOFF.md should match the current shared design-system dependency line")
        #expect(!docs.contains("pinned `.upToNextMinor(from: \"0.3.3\")`"),
                "HANDOFF.md must not leave the recent UI arc pinned to the old MacFaceKit line")
    }

    @Test("public docs describe passive update availability checks")
    func publicDocsDescribePassiveUpdateAvailabilityChecks() {
        for path in ["README.md", "SECURITY.md"] {
            let docs = Self.normalizedWhitespace(Self.file(path))
            #expect(docs.localizedCaseInsensitiveContains("passive update availability check"),
                    "\(path) must describe the launch-time passive update availability check")
            #expect(docs.localizedCaseInsensitiveContains("menu-bar indicator"),
                    "\(path) must mention the update indicator behavior")
            #expect(docs.localizedCaseInsensitiveContains("Check for Updates"),
                    "\(path) must distinguish the user-initiated update command")
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

    @Test("release docs preserve the library-validation boundary")
    func releaseDocsPreserveLibraryValidationBoundary() {
        let decision = Self.file("docs/decisions/0002-notarization-release-gate.md")
        let releasing = Self.file("docs/RELEASING.md")
        for docs in [decision, releasing] {
            #expect(docs.contains("Developer ID"),
                    "release docs must tie the entitlement boundary to Developer ID artifacts")
            #expect(docs.contains("com.apple.security.cs.disable-library-validation"),
                    "release docs must name the local-only library-validation entitlement")
        }
        #expect(decision.contains("must not carry"),
                "the release-gate decision must forbid the local entitlement on public artifacts")
        #expect(releasing.contains("release smoke rejects"),
                "release instructions must say the release smoke rejects the local entitlement")
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

    @Test("public docs explain the permission settings flow")
    func publicDocsExplainPermissionSettingsFlow() {
        let readme = Self.file("README.md")
        let normalizedReadme = Self.normalizedWhitespace(readme)
        for required in [
            "Allow Accessibility",
            "Allow Input Monitoring",
            "open the correct Settings pane",
            "enable the current signed app"
        ] {
            #expect(normalizedReadme.localizedCaseInsensitiveContains(required),
                    "README.md must mention \(required)")
        }
    }

    @Test("public docs describe uninstall privacy cleanup without stale manual-only copy")
    func publicDocsDescribeUninstallPrivacyCleanup() {
        let readme = Self.file("README.md")
        #expect(readme.contains("launch-at-login registration"),
                "README.md must mention login item cleanup")
        #expect(readme.contains("Accessibility/Input Monitoring entries"),
                "README.md must mention scoped privacy cleanup")
        #expect(!readme.contains("the one thing it can't"),
                "README.md must not claim uninstall cannot clean up privacy rows")
    }

    @Test("current app source does not claim privacy permissions are manual-only")
    func currentSourceAvoidsStaleManualOnlyPrivacyCopy() {
        for source in Self.swiftFiles(under: "Sources") {
            #expect(!source.contents.contains("can't be revoked automatically"),
                    "\(source.path) must not contradict the TCC repair/reset implementation")
            #expect(!source.contents.contains("uninstall can't do"),
                    "\(source.path) must not describe privacy reset as impossible")
        }
    }

    @Test("uninstall copy names every partial failure class")
    func uninstallCopyNamesPartialFailureClasses() {
        let menu = Self.file("Sources/TermTile/MenuBarContent.swift")
        #expect(menu.contains("Launch at login could not be deregistered"),
                "uninstall message must explain login-item deregistration failures")
        #expect(menu.contains("couldn't be removed"),
                "uninstall message must explain data removal failures")
        #expect(menu.contains("Drag TermTile.app to the Trash yourself"),
                "uninstall message must explain manual bundle removal")
        #expect(menu.contains("Privacy reset failed"),
                "uninstall message must explain privacy reset failures")
    }

    @Test("accessibility settings action is offered before and after the local trust latch")
    func accessibilitySettingsActionAvailableForBothUntrustedStates() {
        let menu = Self.file("Sources/TermTile/MenuBarContent.swift")
        guard let firstGrant = menu.range(of: "case .needsFirstGrant:"),
              let grantBroken = menu.range(of: "case .grantBroken:"),
              let noticeEnd = menu.range(of: "private func runUninstallFlow") else {
            Issue.record("MenuBarContent.swift must render both untrusted Accessibility states")
            return
        }
        let needsFirstGrantBlock = String(menu[firstGrant.upperBound..<grantBroken.lowerBound])
        let grantBrokenBlock = String(menu[grantBroken.upperBound..<noticeEnd.lowerBound])
        #expect(needsFirstGrantBlock.contains("linkLabel: \"Allow Accessibility\""),
                "first-grant-looking state must offer a direct settings action")
        #expect(grantBrokenBlock.contains("actionLabel: \"Reset & Open Settings\""),
                "grant-broken state must expose the stale-entry reset action")
        #expect(grantBrokenBlock.contains("viewModel.repairAccessibilityPermission()"),
                "grant-broken action must clear TermTile's stale TCC row before opening Settings")
        #expect(!grantBrokenBlock.contains("requestAccessibilityTrust"),
                "settings action must not spawn the extra macOS permission prompt dialog")
    }

    @Test("input monitoring settings action clears stale rows and registers the current app")
    func inputMonitoringSettingsActionClearsStaleRowsAndRegistersCurrentApp() {
        let menu = Self.file("Sources/TermTile/MenuBarContent.swift")
        guard let dragStart = menu.range(of: "SectionCard(\"Drag\""),
              let generalStart = menu.range(of: "SectionCard(\"General\"") else {
            Issue.record("MenuBarContent.swift must keep Drag before General")
            return
        }
        let dragBlock = String(menu[dragStart.lowerBound..<generalStart.lowerBound])
        #expect(dragBlock.contains("actionLabel: \"Allow Input Monitoring\""),
                "Input Monitoring notice should keep one visible button-like action")
        #expect(dragBlock.contains("viewModel.repairInputMonitoringPermission()"),
                "Input Monitoring action should clear stale rows and re-register TermTile before Settings")
        #expect(!dragBlock.contains("resetInputMonitoringPermissionForSettings"),
                "Input Monitoring must not use a reset-only path that can remove the Settings row")
    }

    @Test("Accessibility settings flow has no prompt-backed ViewModel seam")
    func accessibilitySettingsFlowHasNoPromptBackedViewModelSeam() {
        let viewModel = Self.file("Sources/TermTileKit/MenuBarViewModel.swift")
        let app = Self.file("Sources/TermTile/TermTileApp.swift")
        #expect(!viewModel.contains("requestAccessibilityTrust"),
                "Settings-based grant flow should not keep a dormant prompt callback")
        #expect(!viewModel.contains("liveTrustPrompt"),
                "Settings-based grant flow should not expose a prompt-backed live seam")
        #expect(!app.contains("liveTrustPrompt"),
                "The composition root should inject only the non-prompting trust probe")
    }

    @Test("TCC repair process has a bounded wait")
    func permissionRepairProcessWaitIsBounded() {
        let source = Self.file("Sources/TermTileKit/PermissionRepairer.swift")
        #expect(source.contains("processTimeout"),
                "TCC repair must have a named timeout")
        #expect(source.contains("finished.wait(timeout:"),
                "TCC repair must not wait indefinitely on tccutil")
        #expect(source.contains("process.terminate()"),
                "TCC repair must terminate a stuck tccutil process")
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

    @Test("Sparkle remains confined to the executable target")
    func sparkleRemainsConfinedToExecutableTarget() {
        for target in ["Sources/TermTileCore", "Sources/TermTileKit"] {
            for source in Self.swiftFiles(under: target) {
                #expect(!source.contents.contains("import Sparkle"),
                        "\(source.path) must not import Sparkle; update checks belong in the TermTile executable shell")
            }
        }
    }

    @Test("Updater delegates update discovery to Sparkle")
    func updaterDelegatesUpdateDiscoveryToSparkle() {
        let source = Self.file("Sources/TermTile/Updater.swift")
        for forbidden in [
            "URLSession",
            "URLRequest",
            "Data(contentsOf:",
            "XMLParser",
            "NSXMLParser",
            "github.com",
            "appcast.xml"
        ] {
            #expect(!source.contains(forbidden),
                    "Updater.swift must not implement its own update feed discovery with \(forbidden)")
        }
    }

    @Test("MacFaceKit dependency includes the shared attention and notice-action APIs")
    func macFaceKitDependencyIncludesSharedAttentionAndNoticeActionAPIs() {
        let package = Self.file("Package.swift")
        #expect(package.contains(".upToNextMinor(from: \"0.4.2\")"),
                "fresh resolution must start at MacFaceKit v0.4.2 for top-right attention and notice actions")
        let resolved = Self.resolvedVersion(for: "macfacekit")
        #expect(resolved != nil, "Package.resolved must include MacFaceKit")
        #expect(resolved.map { Self.semver($0, isAtLeast: "0.4.2", below: "0.5.0") } == true,
                "TermTile must consume MacFaceKit >= 0.4.2 and < 0.5.0 for shared attention/notice actions")
    }

    @Test("verification commands document the real Swift package gate")
    func verificationCommandsDocumentSwiftGate() {
        let docs = Self.file("docs/verification/COMMANDS.md")
        #expect(docs.contains("scripts/fetch-sparkle.sh && swift build && swift test && swiftlint --strict"),
                "verification commands should document the real Swift package health gate")
        #expect(!docs.localizedCaseInsensitiveContains("npm run check"),
                "TermTile is a Swift package, so verification docs should not point at npm")
    }
}
