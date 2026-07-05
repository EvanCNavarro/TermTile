import Foundation

/// Single source of truth for app identity — one name/bundle-id/URL set everywhere from commit 1. The
/// runtime version/build are NOT here (they come from the bundle via `MacFaceKit.AppInfo`); these are the
/// app-specific CONSTANTS. URLs use `HEAD` (not a branch) so a branch rename never 404s the link.
public enum AppIdentity {
    public static let appName = "TermTile"
    public static let bundleID = "dev.ecn.apps.termtile"

    public static let repoURL = URL(string: "https://github.com/EvanCNavarro/TermTile")!
    public static let licenseURL = URL(string: "https://github.com/EvanCNavarro/TermTile/blob/HEAD/LICENSE")!
}
