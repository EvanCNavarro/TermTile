import AppKit
import MacFaceKit
import SwiftUI

/// The menu-bar logo glyph (replaces the "TermTile" text label). `MenuBarExtra` can flatten/tint
/// SwiftUI label overlays, so the update state uses one original-color composited image rather than a
/// separate SwiftUI badge layer. Falls back to a small drawn grid if the resource can't load, so the
/// menu-bar item is never blank.
struct TermTileGlyph: View {
    let hasAvailableUpdate: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(hasAvailableUpdate: Bool = false) {
        self.hasAvailableUpdate = hasAvailableUpdate
    }

    var body: some View {
        TermTileImage.menuGlyph(hasAvailableUpdate: hasAvailableUpdate, colorScheme: colorScheme)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: TermTileImage.canvasSize.width, height: TermTileImage.canvasSize.height)
        .accessibilityLabel(hasAvailableUpdate ? "Open TermTile, update available" : "Open TermTile")
    }
}

enum TermTileImage {
    static let canvasSize = NSSize(width: 22, height: 18)
    private static let glyphSize = NSSize(width: 18, height: 18)

    static func menuGlyph(hasAvailableUpdate: Bool, colorScheme: ColorScheme) -> Image {
        Image(nsImage: compositedMenuGlyph(hasAvailableUpdate: hasAvailableUpdate,
                                           colorScheme: colorScheme))
    }

    /// Cached source glyph. Loaded from the app bundle's Resources (build-app.sh copies the PDF there);
    /// under `swift run` it is absent, so `sourceGlyph` uses the drawn fallback.
    nonisolated(unsafe) static let nsMenuGlyph: NSImage? = {
        guard let url = Bundle.main.url(forResource: "TermTileMenuGlyph", withExtension: "pdf") else {
            return nil
        }
        let image = NSImage(contentsOf: url)
        image?.size = glyphSize
        image?.isTemplate = false
        return image
    }()

    private static func compositedMenuGlyph(hasAvailableUpdate: Bool, colorScheme: ColorScheme) -> NSImage {
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        drawGlyph(sourceGlyph, color: glyphColor(for: colorScheme))
        if hasAvailableUpdate {
            drawAttentionDot()
        }
        image.isTemplate = false
        return image
    }

    private static var sourceGlyph: NSImage {
        if let nsMenuGlyph { return nsMenuGlyph }
        return fallbackGlyph
    }

    private nonisolated(unsafe) static let fallbackGlyph: NSImage = {
        let image = NSImage(size: glyphSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        let bounds = NSRect(x: 2, y: 2, width: glyphSize.width - 4, height: glyphSize.height - 4)
        path.appendRoundedRect(bounds, xRadius: 2, yRadius: 2)
        path.move(to: NSPoint(x: glyphSize.width / 2, y: bounds.minY))
        path.line(to: NSPoint(x: glyphSize.width / 2, y: bounds.maxY))
        path.move(to: NSPoint(x: bounds.minX, y: glyphSize.height / 2))
        path.line(to: NSPoint(x: bounds.maxX, y: glyphSize.height / 2))
        path.stroke()
        image.isTemplate = false
        return image
    }()

    private static func drawGlyph(_ glyph: NSImage, color: NSColor) {
        let origin = NSPoint(x: 0, y: 0)
        let rect = NSRect(origin: origin, size: glyphSize)
        glyph.draw(in: rect, from: NSRect(origin: .zero, size: glyph.size),
                   operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceIn)
    }

    private static func drawAttentionDot() {
        let size = Tokens.attentionDot
        let rect = NSRect(x: canvasSize.width - size, y: canvasSize.height - size,
                          width: size, height: size)
        let path = NSBezierPath(ovalIn: rect)
        NSColor(Tokens.warning).setFill()
        path.fill()
    }

    private static func glyphColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? .white : .black
    }
}
