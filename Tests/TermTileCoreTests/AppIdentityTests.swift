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
}
