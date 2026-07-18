import Foundation
import Testing
@testable import TermTile

@MainActor
@Suite("Updater availability callbacks")
struct UpdaterAvailabilityCallbackTests {
    @Test("found update marks availability with the display version")
    func foundUpdateMarksAvailability() {
        let updater = Updater(startSession: { _ in nil })

        updater.recordAvailableUpdate(version: "0.2.6")

        #expect(updater.availability == .available(version: "0.2.6"))
        #expect(updater.availability.hasAvailableUpdate)
    }

    @Test("no-update callback clears update attention")
    func noUpdateCallbackClearsUpdateAttention() {
        let updater = Updater(startSession: { _ in nil })
        updater.recordAvailableUpdate(version: "0.2.6")

        updater.recordNoUpdateFound()

        #expect(updater.availability == .unavailable)
        #expect(!updater.availability.hasAvailableUpdate)
    }

    @Test("passive check failure does not request update attention")
    func passiveCheckFailureDoesNotRequestUpdateAttention() {
        let updater = Updater(startSession: { _ in nil })

        updater.recordPassiveAvailabilityCheckFinished(error: TestError.probeFailed)

        #expect(updater.availability == .failed)
        #expect(!updater.availability.hasAvailableUpdate)
    }

    @Test("passive check finish clears checking when no callback supplied a result")
    func passiveCheckFinishClearsCheckingWithoutResult() {
        let fake = CallbackFakeUpdateChecking()
        let updater = Updater(startSession: { _ in StartedUpdateSession(updater: fake) })
        updater.refreshAvailability()

        updater.recordPassiveAvailabilityCheckFinished(error: nil)

        #expect(updater.availability == .unavailable)
    }

    @Test("passive check finish preserves a found update")
    func passiveCheckFinishPreservesFoundUpdate() {
        let updater = Updater(startSession: { _ in nil })
        updater.recordAvailableUpdate(version: "0.2.6")

        updater.recordPassiveAvailabilityCheckFinished(error: nil)

        #expect(updater.availability == .available(version: "0.2.6"))
    }
}

private enum TestError: Error {
    case probeFailed
}

@MainActor
private final class CallbackFakeUpdateChecking: UpdateChecking {
    var canCheckForUpdates = true
    var sessionInProgress = false

    func checkForUpdates() {}

    func checkForUpdateInformation() {}
}
