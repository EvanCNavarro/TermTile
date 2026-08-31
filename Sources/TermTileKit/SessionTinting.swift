import TermTileCore

/// The tint-writing port (ADR-0001 rule 2). Completes the trio with `SessionReading` (AX state)
/// and `TTYProbing` (tty identity).
public protocol SessionTinting: Sendable {
    /// - Returns: `true` if the sequence was written. `false` means nothing was sent — an
    ///   untinted session, never a partially written one.
    @discardableResult
    func setBackground(_ color: TintColor, onTTY tty: String) async -> Bool
}
