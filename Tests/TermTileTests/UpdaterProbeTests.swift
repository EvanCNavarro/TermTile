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
