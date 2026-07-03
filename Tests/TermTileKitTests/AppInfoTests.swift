import Foundation
import Testing
@testable import TermTileKit
import TermTileCore

/// #21a — the display-metadata authority the About panel reads. The load-bearing edge is the
/// unbundled fallback: `swift run`/`swift test` has no Info.plist keys, so a force-unwrap would
/// crash. Version/build read from an injected info dictionary (no disk).
@Suite("AppInfo — display metadata")
struct AppInfoTests {
    @Test("reads version + build from the info dictionary")
    func readsFromDictionary() {
        let info = AppInfo.from(infoDictionary: [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "47",
        ])
        #expect(info.version == "1.2.3")
        #expect(info.build == "47")
    }

    @Test("falls back when keys are absent OR present-but-empty (unbundled dev)")
    func fallback() {
        #expect(AppInfo.from(infoDictionary: nil).version == "dev")
        #expect(AppInfo.from(infoDictionary: nil).build == "0")
        #expect(AppInfo.from(infoDictionary: [:]).version == "dev")
        #expect(AppInfo.from(infoDictionary: ["CFBundleShortVersionString": ""]).version == "dev")
    }

    @Test("name + bundleID are single-sourced from AppIdentity, not re-hardcoded")
    func identityIsSingleSourced() {
        let info = AppInfo(version: "x", build: "y")
        #expect(info.name == AppIdentity.appName)
        #expect(info.bundleID == AppIdentity.bundleID)
    }

    @Test("canonical URLs are the EvanCNavarro/TermTile links")
    func canonicalURLs() {
        let info = AppInfo(version: "x", build: "y")
        #expect(info.repoURL.absoluteString == "https://github.com/EvanCNavarro/TermTile")
        #expect(info.releasesURL.absoluteString == "https://github.com/EvanCNavarro/TermTile/releases/latest")
        #expect(info.licenseURL.absoluteString == "https://github.com/EvanCNavarro/TermTile/blob/HEAD/LICENSE")
    }
}
