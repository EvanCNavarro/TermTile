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
