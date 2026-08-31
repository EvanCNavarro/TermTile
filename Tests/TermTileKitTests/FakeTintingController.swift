@testable import TermTileKit
import TermTileCore

/// Records lifecycle calls so the view model's wiring can be asserted without a real terminal.
actor FakeTintingController: TintingControlling {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var intensities: [ReadyIntensity] = []

    func start() { starts += 1 }
    func stop() { stops += 1 }
    func setReadyIntensity(_ intensity: ReadyIntensity) { intensities.append(intensity) }

    /// Seedable so the view model's refresh can be asserted against a known set.
    var decisions: [TintDecision] = []
    func lastDecisions() -> [TintDecision] { decisions }
    func seed(_ decisions: [TintDecision]) { self.decisions = decisions }
}
