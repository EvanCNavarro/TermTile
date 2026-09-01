import Foundation

/// A background colour for a terminal session.
public struct TintColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Six uppercase hex digits, the form OSC 1337 `SetColors` expects.
    public var hex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

/// The palette, carried over from the out-of-tree tool this replaces.
///
/// ~~so the colours a user already recognises do not change underneath them.~~ **CORRECTED
/// 2026-08-31: that is FALSE.** The hex values match the replaced tool, but the RENDERED colours
/// do not. That tool sets colours over AppleScript, which lands exact; TermTile writes OSC 1337
/// `SetColors`, which iTerm converts. Measured: `#143C22` renders as `#003018` — darker, red
/// channel zeroed. With both writers active a window visibly oscillates between the two.
///
/// **RESOLVED 2026-09-01 (EvanCNavarro/TermTile#29).** The cause was a colour space left
/// unnamed: with no `cs:` prefix iTerm reads an OSC triple as Display P3, while AppleScript's
/// `background color` uses the device space. The hexes below stay exactly as they are — they
/// were always the right REQUEST — and `OSCSequence.setBackground` now declares `rgb:`, the
/// device space, so no conversion happens at all and both write paths mean the same thing by
/// construction. Live-proven: all six render as exactly the hex they ask for.
///
/// A first fix pre-converted the hexes with AppKit instead, and worked — but it depended on
/// iTerm's UNDOCUMENTED default space and carried a 1/255 quantisation residual. Naming the
/// space removes both. The lesson is the general one: reading the protocol's own documentation
/// beat characterising its behaviour empirically, and I did the second first.
public enum TintPalette {
    /// Idle and finished. `#143C22` — dark enough that light terminal text stays readable.
    public static let ready = TintColor(red: 0x14, green: 0x3C, blue: 0x22)
    /// Blocked on a human. `#4A320F` amber.
    public static let blocked = TintColor(red: 0x4A, green: 0x32, blue: 0x0F)
    /// Working, and the resting colour every session returns to. `#111417`.
    public static let normal = TintColor(red: 0x11, green: 0x14, blue: 0x17)

    /// Intensity presets for `ready`, carried over verbatim.
    public static let readySubtle = TintColor(red: 0x0E, green: 0x2B, blue: 0x18)
    public static let readyLouder = TintColor(red: 0x18, green: 0x56, blue: 0x34)
    public static let readyLoudest = TintColor(red: 0x1D, green: 0x75, blue: 0x38)

    /// The colour a state should paint, or `nil` when the state must not be painted at all.
    /// `.unknown` returns `nil` — an unrecognised state is left alone, never guessed (ADR-0006).
    public static func color(for state: AgentState, ready readyColor: TintColor = ready) -> TintColor? {
        switch state {
        case .ready: return readyColor
        case .blocked: return blocked
        case .working: return normal
        case .unknown: return nil
        }
    }
}

/// Builds the escape sequence, and validates where it may be sent.
public enum OSCSequence {
    /// OSC 1337 `SetColors`, proven against live iTerm2 on 2026-08-28 by reading the colour back.
    ///
    /// The `rgb:` prefix NAMES THE COLOUR SPACE, and dropping it is a real bug, not a tidy-up.
    /// `SetColors` accepts `cs:RRGGBB` where `cs` is `srgb`, `rgb` (the device space) or `p3`;
    /// with no prefix iTerm defaults to **Display P3**, so a bare `143C22` renders as `#003018`
    /// with the red channel zeroed. Measured 2026-09-01: `p3:143C22` and bare `143C22` read back
    /// byte-identically, which is what pins the default. `rgb:` is the same device space
    /// AppleScript's `background color` uses, so the palette hex needs NO conversion and the two
    /// write paths cannot drift apart on any display. See EvanCNavarro/TermTile#29.
    public static func setBackground(_ color: TintColor) -> String {
        "\u{1B}]1337;SetColors=bg=rgb:\(color.hex)\u{07}"
    }

    /// Whether `path` is a terminal device this may be written to.
    ///
    /// SAFETY, not tidiness. This writes raw bytes to a filesystem path derived from parsed
    /// process output. Without a shape check, a malformed or hostile `tty` value would make
    /// TermTile write escape sequences into an arbitrary file. Only `/dev/ttysNNN` is accepted,
    /// and the check is on the WHOLE string so nothing can be smuggled through traversal.
    public static func isWritableTerminalDevice(_ path: String) -> Bool {
        let prefix = "/dev/ttys"
        guard path.hasPrefix(prefix) else { return false }
        let suffix = path.dropFirst(prefix.count)
        // Digits ONLY, and at least one. `allSatisfy(\.isNumber)` is true for an EMPTY
        // collection, so "/dev/ttys" would pass without the emptiness check — and `isNumber`
        // accepts non-ASCII digits, so the range test pins it to 0-9. Together these also
        // reject every traversal and NUL-smuggling case, since neither is a digit.
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// User-selectable intensity for the READY tint, persisted by `rawValue`.
///
/// The four steps are the presets the out-of-tree tool shipped, kept identical so a user who
/// already picked one does not have to re-find it here.
public enum ReadyIntensity: String, Equatable, Sendable, CaseIterable {
    case subtle
    case standard
    case louder
    case loudest

    public var color: TintColor {
        switch self {
        case .subtle: return TintPalette.readySubtle
        case .standard: return TintPalette.ready
        case .louder: return TintPalette.readyLouder
        case .loudest: return TintPalette.readyLoudest
        }
    }

    /// What the menu shows.
    public var title: String {
        switch self {
        case .subtle: return "Subtle"
        case .standard: return "Standard"
        case .louder: return "Louder"
        case .loudest: return "Loudest"
        }
    }
}
