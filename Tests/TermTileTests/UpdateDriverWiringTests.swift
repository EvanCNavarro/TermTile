import Foundation
@testable import MacFaceKit
@testable import TermTile
import Testing

/// Pins TermTile's download-flow wiring: its `SPUUserDriver` adapter forwards each Sparkle download
/// callback to the right `UpdateWindowController` method. The controller's morph + byte math are covered
/// in MacFaceKit; this covers the ONLY TermTile-owned code in that flow — the 7 one-line forwards. A
/// mis-wire reddens the screen/heading assertions. No Sparkle rig / server / relaunch.
@MainActor
struct UpdateDriverWiringTests {
    @Test("download callbacks morph the controller: download→progress→preparing→ready→installing→close")
    func downloadCallbacksMorphTheController() async {
        let driver = TermTileUserDriver()
        let model = driver.controller.model

        driver.showDownloadInitiated(cancellation: {})
        guard case let .progress(heading1, _) = model.screen else { Issue.record("expected .progress"); return }
        #expect(heading1 == "Downloading update…")
        #expect(model.fraction == 0)

        driver.showDownloadDidReceiveExpectedContentLength(1000)
        driver.showDownloadDidReceiveData(ofLength: 250)
        #expect(model.fraction == 0.25)

        driver.showDownloadDidStartExtractingUpdate()
        guard case let .progress(heading2, _) = model.screen else { Issue.record("expected .progress"); return }
        #expect(heading2 == "Preparing update…")

        driver.showExtractionReceivedProgress(0.5)
        #expect(model.fraction == 0.5)

        driver.showReady(toInstallAndRelaunch: { _ in })
        guard case .ready = model.screen else { Issue.record("expected .ready"); return }

        driver.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: {})
        guard case let .progress(heading3, _) = model.screen else { Issue.record("expected .progress"); return }
        #expect(heading3 == "Installing…")
        #expect(model.fraction == nil)

        await driver.showUpdateInstalledAndRelaunched(true)   // → controller.close()
    }
}
