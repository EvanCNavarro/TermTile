import CoreGraphics

/// The pure retile POLICY (ADR-0001 rule 1 — the functional core). Maps the tracked windows,
/// in slot order, onto `TileLayout`'s column-of-2 grid and returns the `FrameCommand`s needed
/// to bring them there. This is both the toggle-on path (retile everything) and the core the
/// reducer's create/destroy cases reuse. No clock, no AX, no state — testable with plain values.
///
/// It records NO pending expectations: the ledger is populated by the imperative shell's actor
/// when it ISSUES the AX writes (one pending per write — `MoveClassifier` ledger contract),
/// since only the actor knows the size→pos→size decomposition and the write-time clock.
public enum TileEngine {
    /// Commands to tile `windows` into `config.visibleFrame`. Empty when disabled or when there
    /// are no windows. A command is emitted for slot `k` ONLY when `windows[k]` is not already
    /// within `epsilon` of its target frame — idempotence, so a retile over an already-on-grid
    /// set (a phantom event, a redundant toggle) issues zero writes and causes no feedback churn.
    public static func retileCommands(
        windows: [TrackedWindow],
        config: TileConfig,
        epsilon: CGFloat
    ) -> [FrameCommand] {
        guard config.isEnabled, !windows.isEmpty else { return [] }
        let frames = TileLayout.frames(count: windows.count, visibleFrame: config.visibleFrame, gap: config.gap)
        return zip(windows, frames).compactMap { window, target in
            FrameMath.approximatelyEqual(window.frame, target, epsilon: epsilon)
                ? nil
                : FrameCommand(windowID: window.id, targetFrame: target)
        }
    }
}
