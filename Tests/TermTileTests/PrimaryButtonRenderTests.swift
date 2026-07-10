import AppKit
import Foundation
import MacFaceKit
import SwiftUI
import Testing

@MainActor
@Suite("PrimaryButton Render")
struct PrimaryButtonRenderTests {
    @Test("render the left-aligned primary button")
    func render() throws {
        let view = PrimaryButton("Rearrange now", systemImage: "square.grid.2x2", trailing: "\u{2325}\u{2318}T", action: {})
            .frame(width: 320)
            .padding(12)
            .background(Tokens.panel)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        guard let dir = ProcessInfo.processInfo.environment["TERMTILE_RENDER_DIR"] else { return }
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("primary_button.png"))
    }
}
