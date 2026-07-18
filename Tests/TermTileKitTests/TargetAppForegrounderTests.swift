import Foundation
import Testing
@testable import TermTileKit

@MainActor
@Suite("Target app foregrounding")
struct TargetAppForegrounderTests {
    @Test("no matching running app returns notRunning")
    func notRunning() async {
        let foregrounder = coordinator(apps: [])

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .notRunning)
    }

    @Test("regular running app is preferred over same-bundle non-regular app")
    func regularAppPreferred() async {
        let background = FakeRunningApp(bundleID: "com.example.target", isRegular: false)
        let regular = FakeRunningApp(bundleID: "com.example.target", isRegular: true)
        let foregrounder = coordinator(apps: [background, regular], frontmostBundleID: "com.example.target")

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .frontmost)
        #expect(background.events.isEmpty)
        #expect(regular.events == ["activate"])
    }

    @Test("hidden app is unhidden before activation")
    func hiddenAppUnhiddenBeforeActivate() async {
        let app = FakeRunningApp(bundleID: "com.example.target", isHidden: true)
        let foregrounder = coordinator(apps: [app], frontmostBundleID: "com.example.target")

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .frontmost)
        #expect(app.events == ["unhide", "activate"])
    }

    @Test("activation rejection is reported")
    func activationRejected() async {
        let app = FakeRunningApp(bundleID: "com.example.target", activationAccepted: false)
        let foregrounder = coordinator(apps: [app], frontmostBundleID: "com.example.target")

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .activationRejected)
    }

    @Test("accepted activation that never becomes frontmost is reported honestly")
    func acceptedButUnverified() async {
        let app = FakeRunningApp(bundleID: "com.example.target")
        let foregrounder = coordinator(apps: [app], frontmostBundleID: "com.example.other")

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .requestAcceptedButUnverified)
    }

    @Test("active app is accepted as frontmost even when workspace frontmost is stale")
    func activeAppBeatsStaleFrontmostBundle() async {
        let app = FakeRunningApp(bundleID: "com.example.target", isActiveAfterActivation: true)
        let foregrounder = coordinator(apps: [app], frontmostBundleID: "com.example.other")

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .frontmost)
    }

    @Test("top visible window is accepted as frontmost even when app active is stale")
    func topVisibleWindowBeatsStaleAppSignals() async {
        let app = FakeRunningApp(bundleID: "com.example.target", hasFrontmostVisibleWindowAfterActivation: true)
        let foregrounder = coordinator(apps: [app], frontmostBundleID: "com.example.other")

        let result = await foregrounder.bringToFront(bundleID: "com.example.target")

        #expect(result == .frontmost)
    }

    private func coordinator(apps: [FakeRunningApp], frontmostBundleID: String? = nil)
        -> TargetAppForegroundCoordinator<FakeRunningApp> {
        TargetAppForegroundCoordinator(
            runningApplications: { _ in apps },
            frontmostBundleID: { frontmostBundleID },
            sleep: { _ in },
            pollAttempts: 1)
    }

    final class FakeRunningApp: RunningAppActivating {
        let bundleID: String?
        let isRegular: Bool
        var isHidden: Bool
        let activationAccepted: Bool
        let isActiveAfterActivation: Bool
        let hasFrontmostVisibleWindowAfterActivation: Bool
        private(set) var isActive = false
        private(set) var hasFrontmostVisibleWindow = false
        private(set) var events: [String] = []

        init(bundleID: String?, isRegular: Bool = true, isHidden: Bool = false,
             activationAccepted: Bool = true, isActiveAfterActivation: Bool = false,
             hasFrontmostVisibleWindowAfterActivation: Bool = false) {
            self.bundleID = bundleID
            self.isRegular = isRegular
            self.isHidden = isHidden
            self.activationAccepted = activationAccepted
            self.isActiveAfterActivation = isActiveAfterActivation
            self.hasFrontmostVisibleWindowAfterActivation = hasFrontmostVisibleWindowAfterActivation
        }

        var bundleIdentifier: String? { bundleID }

        func unhide() -> Bool {
            events.append("unhide")
            isHidden = false
            return true
        }

        func activateAllWindows() -> Bool {
            events.append("activate")
            isActive = isActiveAfterActivation
            hasFrontmostVisibleWindow = hasFrontmostVisibleWindowAfterActivation
            return activationAccepted
        }
    }
}
