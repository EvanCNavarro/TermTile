@testable import TermTileCore
import Testing

@Suite("App identity — one name everywhere")
struct AppIdentityTests {
    @Test("app name is TermTile")
    func appName() {
        #expect(AppIdentity.appName == "TermTile")
    }

    @Test("bundle ID is dev.ecn.apps.termtile")
    func bundleID() {
        #expect(AppIdentity.bundleID == "dev.ecn.apps.termtile")
    }

    // Canonical URLs — moved here (#29-B3) when AppInfo was generalized into MacFaceKit; these are
    // TermTile's app-specific constants, so they're pinned in TermTile's own tests, not the shared kit.
    @Test("repo URL")
    func repoURL() {
        #expect(AppIdentity.repoURL.absoluteString == "https://github.com/EvanCNavarro/TermTile")
    }

    @Test("license URL uses HEAD so a branch rename never 404s")
    func licenseURL() {
        #expect(AppIdentity.licenseURL.absoluteString
            == "https://github.com/EvanCNavarro/TermTile/blob/HEAD/LICENSE")
    }
}
