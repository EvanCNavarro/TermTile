import ServiceManagement
@testable import TermTileKit
import Testing

/// #12b — the launch-at-login port. The KEYSTONE (`statusMappingIsFaithful`) pins the one place a
/// real defect would silently corrupt #12c's toggle: the translation from the system
/// `SMAppService.Status` to the Kit-owned `LoginItemStatus`. The fake tests pin the deterministic
/// test-double behavior downstream consumers (#12c) inject. Fakes are per-test instances, so the
/// default `@Test` parallelism is race-free (no shared suite, unlike the live-UserDefaults tests).
@Suite("Launch-at-login — LoginItem port")
struct LoginItemTests {
    @Test("SMAppService.Status maps 1:1 to LoginItemStatus (keystone)")
    func statusMappingIsFaithful() {
        #expect(SMAppServiceLoginItem.map(.notRegistered) == .notRegistered)
        #expect(SMAppServiceLoginItem.map(.enabled) == .enabled)
        #expect(SMAppServiceLoginItem.map(.requiresApproval) == .requiresApproval)
        #expect(SMAppServiceLoginItem.map(.notFound) == .notFound)
    }

    @Test("in-memory fake reports its seeded initial status")
    func fakeReportsSeededStatus() {
        #expect(InMemoryLoginItem().status == .notRegistered)
        #expect(InMemoryLoginItem(initial: .requiresApproval).status == .requiresApproval)
    }

    @Test("fake register() → enabled")
    func fakeRegisterEnables() throws {
        let fake = InMemoryLoginItem()
        try fake.register()
        #expect(fake.status == .enabled)
    }

    @Test("fake unregister() → notRegistered")
    func fakeUnregisterReverts() throws {
        let fake = InMemoryLoginItem(initial: .enabled)
        try fake.unregister()
        #expect(fake.status == .notRegistered)
    }

    @Test("fake round-trips notRegistered → enabled → notRegistered")
    func fakeRoundTrips() throws {
        let fake = InMemoryLoginItem()
        #expect(fake.status == .notRegistered)
        try fake.register()
        #expect(fake.status == .enabled)
        try fake.unregister()
        #expect(fake.status == .notRegistered)
    }
}
