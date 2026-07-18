import Testing
@testable import TermTile

@MainActor
@Suite("Updater passive availability probe")
struct UpdaterProbeTests {
    @Test("refreshAvailability uses Sparkle's passive information check")
    func refreshAvailabilityUsesPassiveInformationCheck() {
        let fake = FakeUpdateChecking()
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })

        updater.refreshAvailability()

        #expect(fake.informationCheckCount == 1)
        #expect(fake.foregroundCheckCount == 0)
        #expect(updater.availability == .checking)
    }

    @Test("refreshAvailability does not start another check during an active session")
    func refreshAvailabilitySkipsActiveSession() {
        let fake = FakeUpdateChecking()
        fake.sessionInProgress = true
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })

        updater.refreshAvailability()

        #expect(fake.informationCheckCount == 0)
        #expect(updater.availability == .unknown)
    }

    @Test("refreshAvailability does not repeat while availability is already checking")
    func refreshAvailabilitySkipsWhileAlreadyChecking() {
        let fake = FakeUpdateChecking()
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })

        updater.refreshAvailability()
        updater.refreshAvailability()

        #expect(fake.informationCheckCount == 1)
    }

    @Test("manual check still uses Sparkle's foreground update flow")
    func manualCheckUsesForegroundUpdateFlow() {
        let fake = FakeUpdateChecking()
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })

        updater.checkForUpdates()

        #expect(fake.foregroundCheckCount == 1)
        #expect(fake.informationCheckCount == 0)
    }

    @Test("available update keeps the menu check command actionable")
    func availableUpdateKeepsMenuCheckCommandActionable() {
        let fake = FakeUpdateChecking()
        fake.canCheckForUpdates = false
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })

        updater.refreshAvailability()
        updater.recordAvailableUpdate(version: "9.9.9")

        #expect(!updater.canCheckForUpdates)
        #expect(updater.canOpenUpdateCheck)
    }

    @Test("available update waits for active Sparkle session to finish before enabling menu command")
    func availableUpdateWaitsForActiveSessionBeforeEnablingMenuCommand() {
        let fake = FakeUpdateChecking()
        fake.canCheckForUpdates = false
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })

        updater.refreshAvailability()
        fake.sessionInProgress = true
        updater.recordAvailableUpdate(version: "9.9.9")

        #expect(!updater.canOpenUpdateCheck)

        fake.sessionInProgress = false
        updater.recordPassiveAvailabilityCheckFinished(error: nil)

        #expect(updater.canOpenUpdateCheck)
    }
}

@MainActor
private final class FakeUpdateChecking: UpdateChecking {
    var canCheckForUpdates = true
    var sessionInProgress = false
    var foregroundCheckCount = 0
    var informationCheckCount = 0

    func checkForUpdates() {
        foregroundCheckCount += 1
    }

    func checkForUpdateInformation() {
        informationCheckCount += 1
    }
}
