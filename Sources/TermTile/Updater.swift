import Foundation
import Observation
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    var sessionInProgress: Bool { get }

    func checkForUpdates()
    func checkForUpdateInformation()
}

extension SPUUpdater: UpdateChecking {}

@MainActor
struct StartedUpdateSession {
    let updater: any UpdateChecking
    let retainedObject: AnyObject?

    init(updater: any UpdateChecking, retainedObject: AnyObject? = nil) {
        self.updater = updater
        self.retainedObject = retainedObject
    }
}

/// TermTile's update primitive. By default it drives Sparkle through `TermTileUserDriver` — the custom
/// user driver — so the update UI is the shared branded dialog (same `MacFaceKit.UpdateWindowController`
/// as RememBar), not Sparkle's stock alert. Sparkle still performs every security-critical step: checks
/// against the `SUFeedURL` appcast, EdDSA-signature verification against `SUPublicEDKey`, download,
/// atomic install, relaunch. A tampered download is refused by Sparkle, not by us.
///
/// Started only by an explicit foreground check or the passive availability probe. The packaged app sets
/// `SUEnableAutomaticChecks` to false so Sparkle does not surface its automatic-check permission prompt in
/// this `.accessory` menu-bar app; the probe uses Sparkle's non-presenting update-information path.
///
/// Rollback is built in: set `TERMTILE_STOCK_UPDATER=1` to use Sparkle's stock
/// `SPUStandardUpdaterController` UI instead, and if the custom updater fails to start it falls back to
/// the stock controller automatically rather than leaving the user unable to update.
@MainActor
@Observable
final class Updater: NSObject {
    @ObservationIgnored private let startSession: (TermTileUserDriver, any SPUUpdaterDelegate) -> StartedUpdateSession?
    @ObservationIgnored private let driver = TermTileUserDriver()
    /// The active updater — nil until the first check starts it (lazy). Once set, it's either our custom
    /// `SPUUpdater` or the stock controller's, so `checkForUpdates`/`canCheckForUpdates` work either way.
    @ObservationIgnored private var updater: (any UpdateChecking)?
    /// Retained when the fallback is in use so the stock controller (which owns its updater) lives on.
    @ObservationIgnored private var retainedUpdaterObject: AnyObject?
    private(set) var availability: UpdateAvailability = .unknown

    init(startSession: @escaping (TermTileUserDriver) -> StartedUpdateSession?) {
        self.startSession = { driver, _ in startSession(driver) }
        super.init()
    }

    override init() {
        self.startSession = Updater.startSparkleSession
        super.init()
    }

    init(startSession: @escaping (TermTileUserDriver, any SPUUpdaterDelegate) -> StartedUpdateSession?) {
        self.startSession = startSession
        super.init()
    }

    /// User-invoked check ("Check for Updates…"). Starts the updater on first use, then checks.
    func checkForUpdates() {
        startIfNeeded()
        updater?.checkForUpdates()
    }

    /// Passive availability probe used by indicators. This must not present Sparkle's update UI.
    func refreshAvailability() {
        guard availability != .checking else { return }
        startIfNeeded()
        guard let updater, !updater.sessionInProgress else { return }
        availability = .checking
        updater.checkForUpdateInformation()
        writeUpdateProbeSmoke("armed")
    }

    func recordAvailableUpdate(version: String?) {
        availability = .available(version: version)
        writeUpdateProbeSmoke("available")
    }

    func recordNoUpdateFound() {
        availability = .unavailable
        writeUpdateProbeSmoke("not-found")
    }

    func recordPassiveAvailabilityCheckFinished(error: (any Error)?) {
        if error != nil {
            availability = .failed
        } else if availability == .checking {
            availability = .unavailable
        }
        writeUpdateProbeSmoke("finished")
    }

    /// Gates the menu item so it disables while a check is in flight. Before the first check the updater
    /// isn't started (lazy), and a check is always initiable — so report `true`; once started, defer to
    /// Sparkle's own state.
    var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? true }

    /// Menu-facing policy: once the passive probe has already found an update, keep the user command
    /// actionable so "Check for Updates" can present the foreground update flow.
    var canOpenUpdateCheck: Bool {
        if availability.hasAvailableUpdate {
            return updater?.sessionInProgress != true
        }
        return canCheckForUpdates
    }

    private func writeUpdateProbeSmoke(_ event: String) {
        guard ProcessInfo.processInfo.environment["TERMTILE_UPDATE_PROBE_SMOKE"] != nil else { return }
        FileHandle.standardError.write(Data("UPDATE_PROBE_SMOKE \(event)\n".utf8))
    }

    private func startIfNeeded() {
        guard updater == nil else { return }
        guard let session = startSession(driver, self) else { return }
        updater = session.updater
        retainedUpdaterObject = session.retainedObject
    }

    private static func startSparkleSession(
        driver: TermTileUserDriver,
        delegate: any SPUUpdaterDelegate
    ) -> StartedUpdateSession {
        let preferStock = ProcessInfo.processInfo.environment["TERMTILE_STOCK_UPDATER"] != nil
        if !preferStock {
            let custom = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: driver,
                delegate: delegate
            )
            if (try? custom.start()) != nil {
                return StartedUpdateSession(updater: custom)
            }
        }

        // Custom updater misconfigured (or rolled back) — fall back to the stock controller so the
        // user can still update. It starts + owns its own updater.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        return StartedUpdateSession(updater: controller.updater, retainedObject: controller)
    }
}

extension Updater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordAvailableUpdate(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        recordNoUpdateFound()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        recordNoUpdateFound()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard updateCheck == .updateInformation else { return }
        recordPassiveAvailabilityCheckFinished(error: error)
    }
}
