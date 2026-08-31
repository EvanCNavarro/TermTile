import Foundation

/// A session's position in iTerm's object model, and NOTHING ELSE.
///
/// SECURITY-CRITICAL BY CONSTRUCTION (ADR-0006 "Privacy surface"). This type is the return value
/// of a function that reads a process ENVIRONMENT BLOCK, and an environment block contains
/// secrets — an `ANTHROPIC_API_KEY` and a `SESSION_SECRET` were exposed in plain text by a single
/// unguarded environment read while this design was being probed.
///
/// The defence is structural, not procedural: three `Int`s cannot carry a credential. There is
/// deliberately no `rawValue`, no `uuid`, no dictionary and no passthrough field — not because
/// they would be misused, but because a type that CAN hold a secret eventually does.
public struct ITermSessionID: Equatable, Sendable {
    public let windowIndex: Int
    public let tabIndex: Int
    public let paneIndex: Int

    public init(windowIndex: Int, tabIndex: Int, paneIndex: Int) {
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.paneIndex = paneIndex
    }
}

/// Extracts `ITERM_SESSION_ID` — and only it — from a raw process environment block.
public enum EnvironmentScan {
    /// The variable this scanner is allowed to see. Anything else in the block is discarded
    /// without being parsed, returned, or logged.
    public static let permittedVariable = "ITERM_SESSION_ID"

    /// - Parameter block: `ps -p <pid> -Eww` output for ONE process — a space-separated run of
    ///   `KEY=VALUE` pairs, most of which are none of TermTile's business.
    /// - Returns: the session's window/tab/pane indices, or `nil` if the variable is absent or
    ///   malformed. The block itself never escapes this function.
    public static func sessionID(fromEnvironmentBlock block: String) -> ITermSessionID? {
        let needle = permittedVariable + "="
        var searchStart = block.startIndex
        // Scan for an occurrence that STARTS a variable — preceded by whitespace or the very
        // beginning. A bare `contains` would also match MY_ITERM_SESSION_ID and read another
        // program's variable as iTerm's.
        while let found = block.range(of: needle, range: searchStart..<block.endIndex) {
            let startsVariable = found.lowerBound == block.startIndex
                || block[block.index(before: found.lowerBound)].isWhitespace
            if startsVariable {
                let value = block[found.upperBound...].prefix { !$0.isWhitespace }
                return parse(value: value)
            }
            searchStart = found.upperBound
        }
        return nil
    }

    /// `w<window>t<tab>p<pane>[:uuid]`. The UUID is dropped at the colon and never parsed — the
    /// indices are the whole join key, so nothing else needs to survive this function.
    private static func parse(value raw: Substring) -> ITermSessionID? {
        let core = raw.prefix { $0 != ":" }
        guard core.first == "w" else { return nil }
        let afterW = core.dropFirst()
        guard let tIndex = afterW.firstIndex(of: "t") else { return nil }
        let afterT = afterW[afterW.index(after: tIndex)...]
        guard let pIndex = afterT.firstIndex(of: "p") else { return nil }

        let windowDigits = afterW[..<tIndex]
        let tabDigits = afterT[..<pIndex]
        let paneDigits = afterT[afterT.index(after: pIndex)...]
        guard let window = wholeNumber(windowDigits),
              let tab = wholeNumber(tabDigits),
              let pane = wholeNumber(paneDigits) else { return nil }
        return ITermSessionID(windowIndex: window, tabIndex: tab, paneIndex: pane)
    }

    /// `Int(_:)` alone would accept "+5" and "-1"; a negative window index is not a thing.
    private static func wholeNumber(_ digits: Substring) -> Int? {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}
