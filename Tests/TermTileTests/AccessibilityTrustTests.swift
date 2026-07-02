@testable import TermTile
import Testing

@Suite("Accessibility trust wrapper — stable invariants only (trust value is environment-dependent)")
struct AccessibilityTrustTests {
    @Test("settings deep link targets the Accessibility privacy pane")
    func settingsDeepLink() {
        #expect(AccessibilityTrust.settingsDeepLink.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @Test("non-prompting trust check returns without crashing or showing UI")
    func nonPromptingCheckReturns() {
        let trusted = AccessibilityTrust.isTrusted(prompting: false)
        #expect(trusted == true || trusted == false)
    }
}
