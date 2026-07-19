import AppKit
import MacFaceKit
import SwiftUI
import Testing
@testable import TermTile

@MainActor
@Suite("TermTile menu-bar glyph")
struct TermTileGlyphTests {
    @Test("MacFaceKit shared attention size is available")
    func macFaceKitSharedAttentionSizeIsAvailable() {
        #expect(Tokens.attentionDot > 0)
    }

    @Test("update badge does not change glyph render size")
    func updateBadgeDoesNotChangeGlyphRenderSize() throws {
        let plainImage = try renderedImage(for: TermTileGlyph())
        let badgedImage = try renderedImage(for: TermTileGlyph(hasAvailableUpdate: true))

        #expect(plainImage.size == badgedImage.size)
    }

    @Test("update badge renders orange-family pixels in the upper-right quadrant")
    func updateBadgeRendersOrangePixelsInUpperRightQuadrant() throws {
        let bitmap = try renderedBitmap(for: TermTileGlyph(hasAvailableUpdate: true))
        let upperRightOrange = orangeFamilyPixels(in: bitmap, xRange: bitmap.pixelsWide / 2..<bitmap.pixelsWide,
                                                  yRange: 0..<bitmap.pixelsHigh / 2)
        let lowerRightOrange = orangeFamilyPixels(in: bitmap, xRange: bitmap.pixelsWide / 2..<bitmap.pixelsWide,
                                                  yRange: bitmap.pixelsHigh / 2..<bitmap.pixelsHigh)

        #expect(upperRightOrange > 0)
        #expect(upperRightOrange > lowerRightOrange)
    }

    @Test("glyph source keeps accessibility label and conditional badge")
    func glyphSourceKeepsAccessibilityLabelAndConditionalBadge() {
        let source = Self.source("Sources/TermTile/TermTileGlyph.swift")

        #expect(source.contains("hasAvailableUpdate"))
        #expect(source.contains("TermTileImage.menuGlyph(hasAvailableUpdate: hasAvailableUpdate"))
        #expect(source.contains(".renderingMode(.original)"))
        #expect(source.contains("Tokens.attentionDot"))
        #expect(source.contains("Tokens.warning"))
        #expect(!source.contains("Circle()"))
        #expect(source.contains("\"Open TermTile\""))
        #expect(source.contains("update available"))
    }

    private func renderedImage(for glyph: TermTileGlyph) throws -> NSImage {
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = 2
        return try #require(renderer.nsImage)
    }

    private func renderedBitmap(for glyph: TermTileGlyph) throws -> NSBitmapImageRep {
        let image = try renderedImage(for: glyph)
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff))
    }

    private func orangeFamilyPixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Int {
        var count = 0
        for x in xRange {
            for y in yRange {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.75,
                   color.greenComponent > 0.35,
                   color.greenComponent < 0.82,
                   color.blueComponent < 0.45,
                   color.redComponent > color.greenComponent,
                   color.greenComponent > color.blueComponent {
                    count += 1
                }
            }
        }
        return count
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
