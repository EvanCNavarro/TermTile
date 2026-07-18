import Foundation
import Observation
import Testing
@testable import TermTile

@MainActor
@Suite("Updater observation")
struct UpdaterObservationTests {
    @Test("availability changes invalidate observation tracking")
    func availabilityChangesInvalidateObservationTracking() async {
        let updater = Updater(startSession: { _ in nil })
        let notifications = LockedCounter()

        withObservationTracking {
            _ = updater.availability.hasAvailableUpdate
        } onChange: {
            notifications.increment()
        }

        updater.recordAvailableUpdate(version: "9.9.9")

        #expect(notifications.value == 1)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
