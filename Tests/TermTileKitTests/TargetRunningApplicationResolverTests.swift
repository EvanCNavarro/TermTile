import Testing
@testable import TermTileKit

@Suite("Target running-app resolution")
struct TargetRunningApplicationResolverTests {
    @Test("preferred app matches bundle id and prefers regular processes")
    func prefersRegularMatchingApp() {
        let helper = FakeRunningApplication(bundleIdentifier: "com.example.target", isRegular: false)
        let regular = FakeRunningApplication(bundleIdentifier: "com.example.target", isRegular: true)
        let other = FakeRunningApplication(bundleIdentifier: "com.example.other", isRegular: true)

        let resolved = TargetRunningApplicationResolver.preferred(
            bundleID: "com.example.target",
            in: [other, helper, regular],
            bundleIdentifier: \.bundleIdentifier,
            isRegular: \.isRegular)

        #expect(resolved == regular)
    }

    @Test("falls back to first matching non-regular app and ignores nil bundle ids")
    func fallsBackToFirstMatchingApp() {
        let nilBundle = FakeRunningApplication(bundleIdentifier: nil, isRegular: true)
        let first = FakeRunningApplication(bundleIdentifier: "com.example.target", isRegular: false)
        let second = FakeRunningApplication(bundleIdentifier: "com.example.target", isRegular: false)

        let resolved = TargetRunningApplicationResolver.preferred(
            bundleID: "com.example.target",
            in: [nilBundle, first, second],
            bundleIdentifier: \.bundleIdentifier,
            isRegular: \.isRegular)

        #expect(resolved == first)
    }

    struct FakeRunningApplication: Equatable {
        var bundleIdentifier: String?
        var isRegular: Bool
    }
}
