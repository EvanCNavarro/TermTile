import AppKit
import SwiftUI
import Testing
@testable import TermTile

@MainActor
@Suite("TermTile menu-bar glyph")
struct TermTileGlyphTests {
    @Test("update badge does not change glyph render size")
    func updateBadgeDoesNotChangeGlyphRenderSize() throws {
        let plainImage = try renderedImage(for: TermTileGlyph())
        let badgedImage = try renderedImage(for: TermTileGlyph(hasAvailableUpdate: true))

        #expect(plainImage.size == badgedImage.size)
    }

    @Test("glyph source keeps accessibility label and conditional badge")
    func glyphSourceKeepsAccessibilityLabelAndConditionalBadge() {
        let source = Self.source("Sources/TermTile/TermTileGlyph.swift")

        #expect(source.contains("hasAvailableUpdate"))
        #expect(source.contains("AttentionDot()"))
        #expect(!source.contains("Circle()"))
        #expect(source.contains("\"Open TermTile\""))
        #expect(source.contains("update available"))
    }

    private func renderedImage(for glyph: TermTileGlyph) throws -> NSImage {
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 2
        return try #require(renderer.nsImage)
    }

    private static func source(_ path: String) -> String {
        let root = repoRoot()
        return (try? String(contentsOf: root.appending(path: path), encoding: .utf8)) ?? ""
    }

    private static func repoRoot() -> URL {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate Package.swift above \(#filePath)")
    }
}
