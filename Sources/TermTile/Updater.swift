import Sparkle
import SwiftUI

/// Minimal Sparkle wiring (stock controller — the "slightly change" from RememBar's custom
/// update UI). `SPUStandardUpdaterController` owns the whole flow: background checks against the
/// `SUFeedURL` appcast, EdDSA-signature verification against `SUPublicEDKey`, download, and the
/// standard update dialogs. `startingUpdater: true` begins scheduled checks at launch.
///
/// An update is only accepted if its `edSignature` (in the appcast) verifies against the public
/// key baked into Info.plist — so a tampered download is refused by Sparkle, not by us.
@MainActor
final class Updater {
    let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    /// User-invoked check ("Check for Updates…"). `canCheckForUpdates` gates the menu item so it
    /// disables while a check is already in flight.
    func checkForUpdates() { controller.updater.checkForUpdates() }
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}
