import Foundation
import TermTileCore

/// Session-tinting lifecycle (#37e2, ADR-0006), split out of `MenuBarViewModel`'s body.
///
/// Not an arbitrary tidy: the class hit SwiftLint's type-body and file-length limits when this
/// landed, and tinting is the one feature whose lifecycle is genuinely separable — it owns a poll
/// loop nothing else touches.
extension MenuBarViewModel {
    /// Refresh the diagnostics from the driver's most recent pass.
    ///
    /// Called when the menu appears. A session that stays its normal colour is otherwise
    /// indistinguishable from a broken feature, and "it is working, it just cannot tell which
    /// window this is" is the single most useful thing the app can say at that moment.
    public func refreshTintDiagnostics() async {
        guard let tinting else { return }
        tintDiagnostics = await tinting.lastDecisions()
    }

    /// Seed the diagnostics directly, for the gallery's rendered check (FL-9).
    ///
    /// Named for its ONE caller rather than as a generic setter: the gallery injects no tinting
    /// controller, so `refreshTintDiagnostics()` finds nothing and the #37f panel would never
    /// render. Mirrors `Updater.recordAvailableUpdate`, which exists for the same reason.
    public func seedTintDiagnosticsForGallery(_ decisions: [TintDecision]) {
        tintDiagnostics = decisions
    }

    /// Start tinting at launch IF the user had it enabled. Called by the composition root after
    /// construction, mirroring `setHotKeyRegistered`.
    ///
    /// Without this the persisted preference would be inert until the user toggled it — the
    /// setting would survive a relaunch while the behaviour silently did not, which reads as the
    /// feature being broken rather than off.
    public func startTintingIfEnabled() {
        guard tintingEnabled, let tinting else { return }
        Task {
            await tinting.setReadyIntensity(readyIntensity)
            await tinting.start()
        }
    }

    /// Toggle opt-in session tinting (#37e2). Persists the preference AND drives the lifecycle:
    /// enabling starts the poll loop, disabling stops it and repaints every touched session back
    /// to normal. Unlike `setReorderOnDrag`, this one is NOT inert — leaving a window tinted after
    /// the user switched the feature off would strand a colour nothing maintains.
    public func setTintingEnabled(_ on: Bool) {
        tintingEnabled = on
        persist()
        guard let tinting else { return }
        Task { on ? await tinting.start() : await tinting.stop() }
    }

    /// Change the READY shade. Persists, and hands it to the driver for the next pass.
    public func setReadyIntensity(_ intensity: ReadyIntensity) {
        readyIntensity = intensity
        persist()
        guard let tinting else { return }
        Task { await tinting.setReadyIntensity(intensity) }
    }
}
