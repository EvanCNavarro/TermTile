import AppKit
import TermTileCore

/// Pre-compensates a palette colour so iTerm2 RENDERS the colour that was asked for.
///
/// ROOT CAUSE (EvanCNavarro/TermTile#29, measured 2026-09-01): iTerm2 interprets an OSC 1337
/// `SetColors` triple as **Display P3**, while its AppleScript `background color` property both
/// sets and reports **Generic RGB**. The same six hex digits mean two different colours
/// depending on which path wrote them, which is why a window written by both TermTile and the
/// out-of-tree poller visibly oscillated between two greens.
///
/// HOW THE SPACES WERE IDENTIFIED, not assumed. Five colours were written over OSC to a scratch
/// window and read back through AppleScript, then every pairing of macOS's RGB colour spaces was
/// applied to the requests and scored against the readings. `displayP3 -> genericRGB` reproduced
/// all five to the 8-bit round with no free parameters; the nearest rival was out by 9. It was
/// then confirmed on HELD-OUT colours picked to split it from `sRGB -> genericRGB` by 92 and 98
/// points, and the terminal matched the Display P3 model on both.
///
/// AppKit does the arithmetic rather than a hand-rolled matrix, because the transform needs
/// Generic RGB's primaries and white point, and guessing those is how a plausible-but-wrong
/// conversion ships. AppKit's prediction was checked against the terminal at full precision:
/// 13.434/255 predicted, 13.432/255 measured.
///
/// RESIDUAL: the compensated value is 8-bit, so a target with no exact 8-bit Display P3
/// preimage lands within 1/255. `#0E2B18` is the one such colour in the palette and renders as
/// `#0D2B18`. That is a property of the colour, not an error in the transform.
///
/// SCOPE: verified on one Mac, one display, one iTerm2 version. Whether iTerm's interpretation
/// tracks the attached display's profile is untested — this machine has a single display. See
/// EvanCNavarro/TermTile#31.
public enum DisplayP3Compensation {
    /// The value to put in the escape sequence so the session ends up showing `color`.
    ///
    /// Fails OPEN to the uncompensated colour: if AppKit cannot convert, the session gets the
    /// wrong shade rather than no tint at all, which is the behaviour that shipped before this.
    public static func oscValue(for color: TintColor) -> TintColor {
        var components: [CGFloat] = [
            CGFloat(color.red) / 255.0,
            CGFloat(color.green) / 255.0,
            CGFloat(color.blue) / 255.0,
            1.0
        ]
        let requested = NSColor(colorSpace: .genericRGB, components: &components, count: 4)
        guard let converted = requested.usingColorSpace(.displayP3) else { return color }
        return TintColor(red: quantise(converted.redComponent),
                         green: quantise(converted.greenComponent),
                         blue: quantise(converted.blueComponent))
    }

    /// Clamps before rounding: a colour outside the destination gamut converts to a component
    /// outside 0...1, and `UInt8(_:)` on that traps rather than saturating.
    private static func quantise(_ value: CGFloat) -> UInt8 {
        UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
    }
}
