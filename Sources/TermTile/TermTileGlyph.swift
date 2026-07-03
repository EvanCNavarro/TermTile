import AppKit
import SwiftUI

/// The menu-bar logo glyph (replaces the "TermTile" text label). Mirrors RememBar's pattern: a
/// bundled vector PDF loaded ONCE as a template `NSImage` (`isTemplate = true` → the system tints it
/// monochrome to the menu bar, adapting to light/dark). Falls back to an SF Symbol if the resource
/// can't load, so the menu-bar item is never blank.
struct TermTileGlyph: View {
    var body: some View {
        TermTileImage.menuGlyph
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Open TermTile")
    }
}

enum TermTileImage {
    private static let glyphSize = NSSize(width: 18, height: 18)

    static var menuGlyph: Image {
        if let image = nsMenuGlyph { return Image(nsImage: image) }
        return Image(systemName: "rectangle.split.3x1")   // fallback: a tiling-ish symbol
    }

    /// Cached: the bundled glyph never changes at runtime, so decode it once. `nonisolated(unsafe)`
    /// because this enum is non-isolated and `NSImage` isn't Sendable; the image is built once here
    /// (size/isTemplate set before first read) and only read afterward. Loaded from the app bundle's
    /// Resources (build-app.sh copies the PDF there); under `swift run` it's absent → SF-Symbol
    /// fallback, which is fine for dev (the glyph only matters in the packaged menu bar).
    nonisolated(unsafe) static let nsMenuGlyph: NSImage? = {
        guard let url = Bundle.main.url(forResource: "TermTileMenuGlyph", withExtension: "pdf") else {
            return nil
        }
        let image = NSImage(contentsOf: url)
        image?.size = glyphSize
        image?.isTemplate = true
        return image
    }()
}
