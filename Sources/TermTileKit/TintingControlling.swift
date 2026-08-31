import TermTileCore

/// The start/stop seam the menu-bar view model drives, so the view model owns tinting's lifecycle
/// without depending on a concrete actor (ADR-0001 rule 2 — a protocol per side-effect surface,
/// with a fake for tests).
public protocol TintingControlling: Sendable {
    func start() async
    /// Stops polling AND resets every touched session — see `TintingDriver.stop()`.
    func stop() async
    /// Applied on the next pass; the driver holds no colour of its own.
    func setReadyIntensity(_ intensity: ReadyIntensity) async
    /// What the most recent pass decided, for the diagnostics surface (#37f).
    ///
    /// PULLED, not pushed. The menu is built when it opens, so it can ask then; a push would mean
    /// the driver holding a reference to the view model and waking it every few seconds to update
    /// a panel nobody has open.
    func lastDecisions() async -> [TintDecision]
}

extension TintingDriver: TintingControlling {}
