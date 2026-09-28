import Foundation

/// A command another local program sends with `open -g termtile://<command>` (zio re-tiles after it opens or
/// closes a session window). Any app or web page can open a custom URL, so this is a strict allowlist: one exact
/// command in the host, nothing else — no path beyond "/", no query, fragment, credentials or port. Pure.
public enum ExternalCommand: Equatable, Sendable {
    case rearrange

    public static let scheme = "termtile"

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == Self.scheme,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let host = parts.host?.lowercased()
        else { return nil }
        switch host {
        case "rearrange": self = .rearrange
        default: return nil
        }
    }
}
