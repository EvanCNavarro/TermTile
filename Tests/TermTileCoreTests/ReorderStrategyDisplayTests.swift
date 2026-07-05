import Testing
@testable import TermTileCore

/// The Picker labels (#29-A). They must be SHORT enough to not truncate in the 280pt popover's
/// "When dragged" row — the strategy's meaning is carried by the section context, not a parenthetical.
@Suite("ReorderStrategy display names")
struct ReorderStrategyDisplayTests {
    @Test("labels are terse (no parenthetical that truncates)")
    func terseLabels() {
        #expect(ReorderStrategy.adaptive.displayName == "Adaptive")
        #expect(ReorderStrategy.swap.displayName == "Swap")
        #expect(ReorderStrategy.columnShift.displayName == "Shift by column")
        #expect(ReorderStrategy.rowShift.displayName == "Shift by row")
    }

    @Test("every case has a non-empty label ≤ 16 chars (fits the picker)")
    func allFit() {
        for strategy in ReorderStrategy.allCases {
            #expect(!strategy.displayName.isEmpty)
            #expect(strategy.displayName.count <= 16)
        }
    }
}
