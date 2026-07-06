import Sparkle

/// TermTile's update primitive. By default it drives Sparkle through `TermTileUserDriver` — the custom
/// user driver — so the update UI is the shared branded dialog (same `MacFaceKit.UpdateWindowController`
/// as RememBar), not Sparkle's stock alert. Sparkle still performs every security-critical step: checks
/// against the `SUFeedURL` appcast, EdDSA-signature verification against `SUPublicEDKey`, download,
/// atomic install, relaunch. A tampered download is refused by Sparkle, not by us.
///
/// Started LAZILY on the first check (never at launch) — matching RememBar's proven design — so it can't
/// surface a no-feed error or the first-launch automatic-check permission prompt (which would steal focus
/// on this `.accessory` menu-bar app) before the user actually asks to check.
///
/// Rollback is built in: set `TERMTILE_STOCK_UPDATER=1` to use Sparkle's stock
/// `SPUStandardUpdaterController` UI instead, and if the custom updater fails to start it falls back to
/// the stock controller automatically rather than leaving the user unable to update.
@MainActor
final class Updater {
    private let driver = TermTileUserDriver()
    /// The active updater — nil until the first check starts it (lazy). Once set, it's either our custom
    /// `SPUUpdater` or the stock controller's, so `checkForUpdates`/`canCheckForUpdates` work either way.
    private var updater: SPUUpdater?
    /// Retained when the fallback is in use so the stock controller (which owns its updater) lives on.
    private var stockController: SPUStandardUpdaterController?

    /// User-invoked check ("Check for Updates…"). Starts the updater on first use, then checks.
    func checkForUpdates() {
        startIfNeeded()
        updater?.checkForUpdates()
    }

    /// Gates the menu item so it disables while a check is in flight. Before the first check the updater
    /// isn't started (lazy), and a check is always initiable — so report `true`; once started, defer to
    /// Sparkle's own state.
    var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? true }

    private func startIfNeeded() {
        guard updater == nil else { return }
        let preferStock = ProcessInfo.processInfo.environment["TERMTILE_STOCK_UPDATER"] != nil
        let custom = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        if !preferStock, (try? custom.start()) != nil {
            updater = custom
        } else {
            // Custom updater misconfigured (or rolled back) — fall back to the stock controller so the
            // user can still update. It starts + owns its own updater.
            let controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            stockController = controller
            updater = controller.updater
        }
    }
}
