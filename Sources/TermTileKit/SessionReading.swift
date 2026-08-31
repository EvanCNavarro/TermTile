import TermTileCore

/// The session-observation port (ADR-0001 rule 2, mirroring `WindowSystem`).
///
/// One seam for "what panes are visible and what is on them", so the tinting coordinator can be
/// driven by plain values in tests. The production adapter is `AXSessionReader`; the test adapter
/// is an in-memory fake. `async` for the same reason `WindowSystem` is: an `actor` adapter can
/// only witness a `Sendable` protocol requirement when the requirement is `async`.
public protocol SessionReading: Sendable {
    /// Panes visible right now across the target app's windows.
    ///
    /// ACTIVE TABS ONLY — AX does not expose background tabs at all (ADR-0006 finding 6). That
    /// is not a defect to route around: a background tab's background colour is not rendered, so
    /// the blind spot coincides with what the user cannot see.
    func visiblePanes() async -> [ObservedPane]
}
