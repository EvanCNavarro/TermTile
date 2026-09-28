import Foundation

/// A command another local program sends with `open -g termtile://<command>` (zio tiles after it
/// opens a window). RED-FIRST STUB: rejects everything until the allowlist is implemented.
public enum ExternalCommand: Equatable, Sendable {
    case rearrange

    public init?(url: URL) {
        return nil
    }
}
