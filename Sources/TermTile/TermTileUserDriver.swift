import AppKit
import MacFaceKit
import Sparkle

/// TermTile's app icon for the update dialog (bundled so it renders under `swift run`/gallery too).
var termTileUpdateIcon: NSImage? {
    Bundle.packagedResourceURL("AppIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

/// TermTile's custom Sparkle user driver — a THIN adapter that translates Sparkle's `SPUUserDriver`
/// callbacks into the shared `MacFaceKit.UpdateWindowController`'s semantic `show*` API, so TermTile
/// shows the same branded update dialog as RememBar (differing only in name + icon). All the window
/// hosting, morph, escape/acknowledgement and progress math live once in the kit controller; this file
/// is pure Sparkle→controller translation — the irreducible Sparkle-coupled shell, app-local because
/// Sparkle is a vendored binaryTarget that can't live in the public kit. Sparkle still performs every
/// security-critical step (download, EdDSA verification, atomic install, relaunch).
@MainActor
final class TermTileUserDriver: NSObject, SPUUserDriver {
    private let controller = UpdateWindowController(appName: "TermTile", icon: termTileUpdateIcon)

    /// The running app's version, shown on the "you have X" / up-to-date lines (the shared reader;
    /// `"dev"` when unbundled).
    private var currentAppVersion: String {
        AppInfo.fromBundle().version
    }

    // MARK: SPUUserDriver — required

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        controller.showPermission(
            onAllow: { reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)) },
            onDecline: { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) })
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        controller.showChecking(onCancel: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        controller.showAvailable(
            version: appcastItem.displayVersionString,
            currentVersion: currentAppVersion,
            // Embedded notes only (a downloaded releaseNotesLink arrives later via showUpdateReleaseNotes);
            // the gate + parse live once in the kit.
            notes: ReleaseNotesParser.embeddedItems(
                releaseNotesURL: appcastItem.releaseNotesURL,
                description: appcastItem.itemDescription,
                format: ReleaseNotesFormat(sparkleFormat: appcastItem.itemDescriptionFormat)),
            onInstall: { reply(.install) },
            onRemindLater: { reply(.dismiss) })
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard let items = ReleaseNotesParser.items(from: downloadData.data) else { return }
        controller.updateReleaseNotes(items)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // No inline notes to show; the dialog simply omits the "What's new" section.
    }

    func showUpdateNotFoundWithError(_ error: Error) async {
        await controller.showUpToDate(version: currentAppVersion)
    }

    func showUpdaterError(_ error: Error) async {
        await controller.showError(message: error.localizedDescription)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        controller.showDownloadStarting(onCancel: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        controller.setExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        controller.addReceivedBytes(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        controller.showPreparing()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        controller.updateProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        controller.showReady(onRestart: { reply(.install) }, onDismiss: { reply(.dismiss) })
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        controller.showInstalling()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
        controller.close()
    }

    func dismissUpdateInstallation() {
        controller.close()
    }

    // MARK: SPUUserDriver — optional

    func showUpdateInFocus() {
        controller.showInFocus()
    }
}
