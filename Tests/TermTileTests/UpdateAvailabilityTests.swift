import Testing
@testable import TermTile

@Suite("Update availability state")
struct UpdateAvailabilityTests {
    @Test("unknown availability does not request attention")
    func unknownAvailabilityDoesNotRequestAttention() {
        #expect(!UpdateAvailability.unknown.hasAvailableUpdate)
    }

    @Test("available update requests attention")
    func availableUpdateRequestsAttention() {
        #expect(UpdateAvailability.available(version: "0.2.6").hasAvailableUpdate)
    }

    @Test("non-available states do not request attention")
    func nonAvailableStatesDoNotRequestAttention() {
        for state in [
            UpdateAvailability.checking,
            .unavailable,
            .failed
        ] {
            #expect(!state.hasAvailableUpdate)
        }
    }
}
