import TermTileCore

/// The tty-side port (ADR-0001 rule 2): "which agent sessions exist, and where do they sit in
/// iTerm's object model". Pairs with `SessionReading`, which answers the AX side.
public protocol TTYProbing: Sendable {
    func sessions() async -> [TTYSessionSnapshot]
}
