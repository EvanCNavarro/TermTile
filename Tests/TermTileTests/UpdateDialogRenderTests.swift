import AppKit
import Foundation
import MacFaceKit
import SwiftUI
@testable import TermTile
import Testing

/// Offscreen PNG renders of the shared update dialog with TermTile's branding (name + icon), proving
/// TermTile shows the same `MacFaceKit.UpdateDialog` as RememBar — the point of Phase B. Gated on
/// TERMTILE_RENDER_DIR. Not pixel assertions.
@MainActor
@Suite("TermTile Update Dialog Render")
struct UpdateDialogRenderTests {
    private static let notes = [
        "Rearranges your terminal windows into a tidy, even grid",
        "Pick which app to tile and the gap between windows",
        "Toggle tiling from the menu bar or a global shortcut"
    ]

    @Test("render the TermTile-branded update states")
    func renderStates() throws {
        try render(UpdateDialog.permission(appName: "TermTile", onAllow: {}, onDecline: {}), "tt_permission.png")
        try render(UpdateDialog.available(appName: "TermTile", version: "0.2.0", currentVersion: "0.1.0",
                                          notes: Self.notes, notesExpanded: .constant(true),
                                          onInstall: {}, onRemindLater: {}), "tt_available.png")
        try render(UpdateDialog.progress(appName: "TermTile", heading: "Downloading update…", version: "0.2.0",
                                         fraction: 0.62, onCancel: {}), "tt_progress.png")
        try render(UpdateDialog.upToDate(appName: "TermTile", version: "0.2.0", onOK: {}), "tt_uptodate.png")
    }

    private func render(_ dialog: UpdateDialog, _ name: String) throws {
        let framed = dialog.icon(termTileUpdateIcon)
            .background(Tokens.updateWindow)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        guard let dir = ProcessInfo.processInfo.environment["TERMTILE_RENDER_DIR"] else { return }
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }
}
