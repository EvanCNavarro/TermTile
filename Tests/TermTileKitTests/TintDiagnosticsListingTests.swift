import CoreGraphics
@testable import TermTileKit
import TermTileCore
import Testing

/// The menu listed EVERY session, which is mostly noise: a painted session already says what it
/// is by being coloured. The panel's stated job (#37f) is to explain a session that could NOT be
/// painted, so that is what it should list — and a count for the rest.
@Suite("Tint diagnostics listing")
@MainActor
struct TintDiagnosticsListingTests {
    /// Mirrors the gallery seed: three painted, two not, one of those unjoinable.
    static let seeded: [TintDecision] = [
        TintDecision(cwd: "termtile", tty: "/dev/ttys005", state: .ready, wrote: true, hadBaseline: true),
        TintDecision(cwd: "changefabric", tty: "/dev/ttys000", state: .working, wrote: true, hadBaseline: true),
        TintDecision(cwd: "invela", tty: "/dev/ttys003", state: .blocked, wrote: true, hadBaseline: true),
        TintDecision(cwd: "portfolio", tty: "/dev/ttys004", state: .unknown, wrote: false, hadBaseline: false),
        TintDecision(cwd: "shared-folder", tty: nil, state: .unknown, wrote: false, ambiguity: .cwdNotUnique)
    ]

    /// Same construction the tinting-lifecycle suite uses, so this test exercises the real VM
    /// rather than a shape invented for it.
    private static func viewModel(_ decisions: [TintDecision] = seeded) -> MenuBarViewModel {
        let (vm, _, _) = MenuBarViewModelTintingTests.make(enabled: true)
        vm.seedTintDiagnosticsForGallery(decisions)
        return vm
    }

    @Test("only the sessions that could not be painted are listed")
    func listsOnlyUnexplained() {
        let vm = Self.viewModel()
        #expect(vm.tintDiagnostics.count == 5, "fixture drifted")
        let listed = vm.unexplainedTintDiagnostics.map(\.cwd)
        #expect(listed == ["portfolio", "shared-folder"], "listed \(listed)")
    }

    @Test("the painted ones are counted, not named")
    func countsThePainted() {
        #expect(Self.viewModel().tintedSessionCount == 3)
    }

    /// The all-fine case is the common one, and it must produce an EMPTY list — otherwise the
    /// change buys nothing on the screen the user actually sees most of the time.
    @Test("when every session is painted, nothing is listed")
    func nothingToListWhenAllPainted() {
        let vm = Self.viewModel(Self.seeded.filter { $0.wrote })
        #expect(vm.unexplainedTintDiagnostics.isEmpty)
        #expect(vm.tintedSessionCount == 3)
    }
}
