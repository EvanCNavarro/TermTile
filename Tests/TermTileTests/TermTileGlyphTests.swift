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

    @Test("update badge renders orange-family pixels at the top-right canvas edge")
    func updateBadgeRendersOrangePixelsAtTopRightCanvasEdge() throws {
        let bitmap = try renderedBitmap(for: TermTileGlyph(hasAvailableUpdate: true))
        let orangeBounds = try #require(pixelBounds(in: bitmap, where: isOrangeFamily(_:)))
        let upperRightOrange = orangeFamilyPixels(in: bitmap, xRange: bitmap.pixelsWide / 2..<bitmap.pixelsWide,
                                                  yRange: 0..<bitmap.pixelsHigh / 2)
        let lowerRightOrange = orangeFamilyPixels(in: bitmap, xRange: bitmap.pixelsWide / 2..<bitmap.pixelsWide,
                                                  yRange: bitmap.pixelsHigh / 2..<bitmap.pixelsHigh)

        #expect(orangeBounds.maxX >= bitmap.pixelsWide - 4,
                "badge should reach the right edge region, got maxX \(orangeBounds.maxX)")
        #expect(orangeBounds.minY <= 3,
                "badge should reach the top edge region, got minY \(orangeBounds.minY)")
        #expect(upperRightOrange > 0)
        #expect(upperRightOrange > lowerRightOrange)
    }

    @Test("unbadged glyph visible bounds stay centered in the reserved badge canvas")
    func unbadgedGlyphVisibleBoundsStayCenteredInReservedBadgeCanvas() throws {
        let bitmap = try renderedBitmap(for: TermTileGlyph())
        let bounds = try #require(pixelBounds(in: bitmap, where: isVisible(_:)))
        let contentMidX = bounds.midX
        let canvasMidX = Double(bitmap.pixelsWide - 1) / 2

        #expect(abs(contentMidX - canvasMidX) <= 1,
                "visible glyph center \(contentMidX) should align with canvas center \(canvasMidX)")
    }

    @Test("source menu glyph artwork is horizontally centered before badge compositing")
    func sourceMenuGlyphArtworkIsHorizontallyCenteredBeforeBadgeCompositing() throws {
        let svgURL = Self.repoRoot().appending(path: "Resources/TermTileMenuGlyph.svg")
        let document = try XMLDocument(contentsOf: svgURL)
        let root = try #require(document.rootElement())
        let canvasWidth = try numericAttribute("width", in: root)
        let rects = try #require(try root.nodes(forXPath: "//*[local-name()='rect']") as? [XMLElement])
        let rectBounds = try rects.map { rect in
            let x = try numericAttribute("x", in: rect)
            let width = try numericAttribute("width", in: rect)
            return (minX: x, maxX: x + width)
        }
        let artMinX = try #require(rectBounds.map(\.minX).min())
        let artMaxX = try #require(rectBounds.map(\.maxX).max())
        let artMidX = (artMinX + artMaxX) / 2
        let canvasMidX = canvasWidth / 2

        #expect(abs(artMidX - canvasMidX) < 0.001,
                "source artwork center \(artMidX) should align with source canvas center \(canvasMidX)")
    }

    @Test("shipped PDF menu glyph artwork is horizontally centered before badge compositing")
    func shippedPDFMenuGlyphArtworkIsHorizontallyCenteredBeforeBadgeCompositing() throws {
        let pdfURL = Self.repoRoot().appending(path: "Resources/TermTileMenuGlyph.pdf")
        let image = try #require(NSImage(contentsOf: pdfURL))
        image.size = NSSize(width: 18, height: 18)
        let bitmap = try rasterizedBitmap(for: image)
        let bounds = try #require(pixelBounds(in: bitmap, where: isVisible(_:)))
        let contentMidX = bounds.midX
        let canvasMidX = Double(bitmap.pixelsWide - 1) / 2

        #expect(abs(contentMidX - canvasMidX) <= 1,
                "PDF glyph center \(contentMidX) should align with PDF canvas center \(canvasMidX)")
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

    private func rasterizedBitmap(for source: NSImage) throws -> NSBitmapImageRep {
        let scale = 2
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(source.size.width) * scale,
            pixelsHigh: Int(source.size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = source.size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: source.size),
                    from: NSRect(origin: .zero, size: source.size),
                    operation: .sourceOver,
                    fraction: 1)
        return rep
    }

    private struct PixelBounds {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        var midX: Double {
            Double(minX + maxX) / 2
        }
    }

    private func orangeFamilyPixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Int {
        countPixels(in: bitmap, xRange: xRange, yRange: yRange, where: isOrangeFamily(_:))
    }

    private func countPixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>,
        where predicate: (NSColor) -> Bool
    ) -> Int {
        var count = 0
        for x in xRange {
            for y in yRange {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if predicate(color) {
                    count += 1
                }
            }
        }
        return count
    }

    private func pixelBounds(
        in bitmap: NSBitmapImageRep,
        where predicate: (NSColor) -> Bool
    ) -> PixelBounds? {
        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = -1
        var maxY = -1

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if !predicate(color) { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return PixelBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func isVisible(_ color: NSColor) -> Bool {
        color.alphaComponent > 0.2
    }

    private func isOrangeFamily(_ color: NSColor) -> Bool {
        guard let color = color.usingColorSpace(.sRGB) else { return false }
        return color.redComponent > 0.75
            && color.greenComponent > 0.35
            && color.greenComponent < 0.82
            && color.blueComponent < 0.45
            && color.redComponent > color.greenComponent
            && color.greenComponent > color.blueComponent
    }

    private func numericAttribute(_ name: String, in element: XMLElement) throws -> Double {
        let value = try #require(element.attribute(forName: name)?.stringValue)
        return try #require(Double(value))
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
